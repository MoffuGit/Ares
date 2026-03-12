const std = @import("std");
const xev = @import("../global.zig").xev;
const Allocator = std.mem.Allocator;
const Thread = @import("Thread.zig");

const log = std.log.scoped(.monitor);

pub const Monitor = @This();

pub const WatchRequest = struct {
    id: u64,
    path: []u8,
    alloc: Allocator,
    userdata: ?*anyopaque,
    callback: *const fn (userdata: ?*anyopaque, id: u64, events: u32) void,
};

pub const WatcherEntry = struct {
    watcher: xev.FileSystem.Watcher,
    path: []u8,
    id: u64,
    pending_events: u32 = 0,
    dirty: bool = false,
    monitor: *Monitor,
    userdata: ?*anyopaque,
    callback: *const fn (userdata: ?*anyopaque, id: u64, events: u32) void,
};

alloc: Allocator,
watchers: std.AutoHashMap(u64, *WatcherEntry),
pending_cancel: std.ArrayListUnmanaged(*WatcherEntry),
dirty_queue: std.ArrayListUnmanaged(*WatcherEntry),
next_id: u64 = 0,
thread: Thread,
thr: std.Thread,

pub fn create(alloc: Allocator) !*Monitor {
    const monitor = try alloc.create(Monitor);

    monitor.* = .{
        .alloc = alloc,
        .watchers = std.AutoHashMap(u64, *WatcherEntry).init(alloc),
        .pending_cancel = .{},
        .dirty_queue = .{},
        .thread = try Thread.init(alloc, monitor),
        .thr = undefined,
    };

    monitor.thr = try std.Thread.spawn(.{}, Thread.threadMain, .{&monitor.thread});

    return monitor;
}

pub fn destroy(self: *Monitor) void {
    {
        self.thread.stop.notify() catch |err| {
            log.err("error notifying monitor thread to stop, may stall err={}", .{err});
        };
        self.thr.join();
    }

    self.thread.deinit();

    var it = self.watchers.valueIterator();
    while (it.next()) |entry_ptr| {
        const entry = entry_ptr.*;
        self.alloc.free(entry.path);
        self.alloc.destroy(entry);
    }
    self.watchers.deinit();

    for (self.pending_cancel.items) |entry| {
        self.alloc.free(entry.path);
        self.alloc.destroy(entry);
    }
    self.pending_cancel.deinit(self.alloc);
    self.dirty_queue.deinit(self.alloc);

    self.alloc.destroy(self);

    log.info("Monitor closed", .{});
}

pub fn userdataValue(comptime Userdata: type, v: ?*anyopaque) ?*Userdata {
    // Void userdata is always a null pointer.
    if (Userdata == void) return null;
    return @ptrCast(@alignCast(v));
}

pub fn watchPath(
    self: *Monitor,
    abs_path: []const u8,
    comptime Userdata: type,
    userdata: ?*Userdata,
    comptime callback: *const fn (userdata: ?*Userdata, id: u64, events: u32) void,
) !u64 {
    const id = self.next_id;
    self.next_id += 1;

    const path = try self.alloc.dupe(u8, abs_path);

    const entry = self.alloc.create(WatcherEntry) catch {
        log.err("failed to allocate watcher entry", .{});
        self.alloc.free(path);
        return error.OutOfMemory;
    };

    entry.* = .{
        .watcher = .{},
        .path = path,
        .id = id,
        .monitor = self,
        .userdata = userdata,
        .callback = (struct {
            fn cb(inner_userdata: ?*anyopaque, inner_id: u64, inner_events: u32) void {
                return @call(.always_inline, callback, .{ userdataValue(Userdata, inner_userdata), inner_id, inner_events });
            }
        }.cb),
    };

    self.thread.fs.watch(path, &entry.watcher, WatcherEntry, entry, fsEventsCallback) catch |err| {
        log.err("failed to start watcher for '{s}': {}", .{ path, err });
        self.alloc.free(path);
        self.alloc.destroy(entry);
        return error.OutOfMemory;
    };

    self.watchers.put(id, entry) catch {
        log.err("failed to track watcher id={}", .{id});
        self.thread.fs.cancel(&entry.watcher);
        self.alloc.free(entry.path);
        self.alloc.destroy(entry);
        return error.OutOfMemory;
    };

    return id;
}

fn fsEventsCallback(
    entry: ?*Monitor.WatcherEntry,
    _: *xev.FileSystem.Watcher,
    _: []const u8,
    events: u32,
) xev.CallbackAction {
    const e = entry orelse return .rearm;
    e.pending_events |= events;
    if (!e.dirty) {
        e.dirty = true;
        e.monitor.dirty_queue.append(e.monitor.alloc, e) catch {};
    }
    return .rearm;
}

pub fn unwatch(self: *Monitor, id: u64) void {
    if (self.thread.mailbox.push(.{ .remove = id }, .instant) != 0) {
        self.thread.wakeup.notify() catch |err| {
            log.err("error notifying monitor thread to wakeup: {}", .{err});
        };
    }
}

pub fn addWatcher(
    self: *Monitor,
    fs: *xev.FileSystem,
    req: *WatchRequest,
    comptime callback: *const fn (?*WatcherEntry, *xev.FileSystem.Watcher, []const u8, u32) xev.CallbackAction,
) void {
    const id = req.id;

    const entry = self.alloc.create(WatcherEntry) catch {
        log.err("failed to allocate watcher entry", .{});
        self.alloc.free(req.path);
        self.alloc.destroy(req);
        return;
    };

    entry.* = .{
        .watcher = .{},
        .path = req.path,
        .id = id,
        .monitor = self,
        .userdata = req.userdata,
        .callback = req.callback,
    };

    fs.watch(req.path, &entry.watcher, WatcherEntry, entry, callback) catch |err| {
        log.err("failed to start watcher for '{s}': {}", .{ req.path, err });
        self.alloc.free(req.path);
        self.alloc.destroy(entry);
        self.alloc.destroy(req);
        return;
    };

    self.watchers.put(id, entry) catch {
        log.err("failed to track watcher id={}", .{id});
        fs.cancel(&entry.watcher);
        self.alloc.free(entry.path);
        self.alloc.destroy(entry);
        self.alloc.destroy(req);
        return;
    };

    self.alloc.destroy(req);
}

pub fn removeWatcher(self: *Monitor, fs: *xev.FileSystem, id: u64) void {
    if (self.watchers.fetchRemove(id)) |kv| {
        const entry = kv.value;
        entry.pending_events = 0;
        entry.dirty = false;
        fs.cancel(&entry.watcher);
        self.pending_cancel.append(self.alloc, entry) catch |err| {
            log.err("failed to add watcher to pending_cancel queue: {}", .{err});
            self.alloc.free(entry.path);
            self.alloc.destroy(entry);
        };
        log.debug("monitor removing watcher: id={}", .{id});
    } else {
        log.warn("no watcher found for id={}", .{id});
    }
}

pub fn cleanupCancelledWatchers(self: *Monitor) void {
    var i: usize = 0;
    while (i < self.pending_cancel.items.len) {
        const entry = self.pending_cancel.items[i];
        if (entry.watcher.state() == .dead) {
            log.debug("cleaning up dead watcher for id={}", .{entry.id});
            self.alloc.free(entry.path);
            self.alloc.destroy(entry);
            _ = self.pending_cancel.swapRemove(i);
        } else {
            i += 1;
        }
    }
}

pub fn flushPendingEvents(self: *Monitor) void {
    for (self.dirty_queue.items) |entry| {
        const events = entry.pending_events;
        entry.pending_events = 0;
        entry.dirty = false;
        if (events != 0) {
            entry.callback(entry.userdata, entry.id, events);
        }
    }
    self.dirty_queue.clearRetainingCapacity();
}

const testing = std.testing;

const TestState = struct {
    received_id: std.atomic.Value(u64) = .{ .raw = std.math.maxInt(u64) },
    received_events: std.atomic.Value(u32) = .{ .raw = 0 },
    callback_count: std.atomic.Value(u32) = .{ .raw = 0 },

    fn callback(self_: ?*TestState, id: u64, events: u32) void {
        const self = self_.?;
        self.received_id.store(id, .release);
        _ = self.received_events.fetchOr(events, .release);
        _ = self.callback_count.fetchAdd(1, .release);
    }
};

fn sleep(ms: u64) void {
    std.Thread.sleep(ms * std.time.ns_per_ms);
}

test "watchPath receives fs events" {
    const alloc = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const abs_path = try tmp.dir.realpath(".", &path_buf);

    const monitor = try Monitor.create(alloc);
    defer monitor.destroy();

    var state = TestState{};
    const id = try monitor.watchPath(abs_path, TestState, &state, TestState.callback);

    sleep(200);

    const file = try tmp.dir.createFile("test.txt", .{});
    file.close();

    sleep(300);

    try testing.expect(state.callback_count.load(.acquire) > 0);
    try testing.expectEqual(id, state.received_id.load(.acquire));
}

test "events are merged within flush interval" {
    const alloc = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const abs_path = try tmp.dir.realpath(".", &path_buf);

    const monitor = try Monitor.create(alloc);
    defer monitor.destroy();

    var state = TestState{};
    _ = try monitor.watchPath(abs_path, TestState, &state, TestState.callback);

    sleep(200);

    // Rapid writes — should merge into fewer callbacks than file count
    for (0..10) |i| {
        var name_buf: [32]u8 = undefined;
        const name = std.fmt.bufPrint(&name_buf, "file_{}.txt", .{i}) catch unreachable;
        const f = try tmp.dir.createFile(name, .{});
        f.close();
    }

    sleep(300);

    const count = state.callback_count.load(.acquire);
    try testing.expect(count > 0);
    try testing.expect(count < 10);
}

test "unwatch stops receiving events" {
    const alloc = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const abs_path = try tmp.dir.realpath(".", &path_buf);

    const monitor = try Monitor.create(alloc);
    defer monitor.destroy();

    var state = TestState{};
    const id = try monitor.watchPath(abs_path, TestState, &state, TestState.callback);

    sleep(200);

    const f1 = try tmp.dir.createFile("before.txt", .{});
    f1.close();

    sleep(300);

    const count_before = state.callback_count.load(.acquire);
    try testing.expect(count_before > 0);

    monitor.unwatch(id);

    sleep(200);

    const f2 = try tmp.dir.createFile("after.txt", .{});
    f2.close();

    sleep(300);

    const count_after = state.callback_count.load(.acquire);
    try testing.expectEqual(count_before, count_after);
}

//NOTE:
//At some point i tried to move the calls of the fs to the Thread,
//this give me a weird behaviour, i stop doing that because i didnt really see any
//change on performance when i move the fs calls to the scanner thread:
// Is really weird that the monitor fails that much, and even more that fails with
// the next two cases:
// a completion has the next field set and not null
// a completion is active
//
// for me this don't make sense because there should not be a case where the same completion is used twice
// for every watcher request we create a watcher entry (this watcher entry has his own completion and watcher)
// and even if two watchers share hte same path, the xev system handle that case as well
// is not the callback becasue they don't get to trigger during the filetree set up,
//
// this don't make sense:
// [1] error(libxev_kqueue): invalid state in submission queue state=.active
// [1] error(libxev_kqueue): invalid state in submission queue state=.active
// [1] error(libxev_kqueue): invalid state in submission queue state=.active
// [1] error(libxev_kqueue): invalid state in submission queue state=.active
// [1] error(libxev_kqueue): invalid state in submission queue state=.active
// [1] error(libxev_kqueue): invalid state in submission queue state=.active
// [1] error(libxev_kqueue): invalid state in submission queue state=.active                                         [1] error(libxev_kqueue): invalid state in submission queue state=.active
// [1] error(libxev_kqueue): invalid state in submission queue state=.active
// [1] error(libxev_kqueue): invalid state in submission queue state=.active
// [1] error(libxev_kqueue): invalid state in submission queue state=.active
// [1] error(libxev_kqueue): invalid state in submission queue state=.active                                         [1] error(libxev_kqueue): invalid state in submission queue state=.active                                         [1] error(libxev_kqueue): invalid state in submission queue state=.active                                         [1] error(libxev_kqueue): invalid state in submission queue state=.active                                         [1] error(libxev_kqueue): invalid state in submission queue state=.active                                         [1] error(libxev_kqueue): invalid state in submission queue state=.active                                         [1] error(libxev_kqueue): invalid state in submission queue state=.active                                         [1] error(libxev_kqueue): invalid state in submission queue state=.active                                         [1] error(libxev_kqueue): invalid state in submission queue state=.active                                         [1] error(libxev_kqueue): invalid state in submission queue state=.active[1] error(libxev_kqueue): invalid state in submission queue state=.active
// [1] error(libxev_kqueue): invalid state in submission queue state=.active
// [1] error(libxev_kqueue): invalid state in submission queue state=.active
// [1] error(libxev_kqueue): invalid state in submission queue state=.active
// [1] error(libxev_kqueue): invalid state in submission queue state=.active
// [1] error(libxev_kqueue): invalid state in submission queue state=.active
// [1] error(libxev_kqueue): invalid state in submission queue state=.active
// [1] error(libxev_kqueue): invalid state in submission queue state=.active
// [1] error(libxev_kqueue): invalid state in submission queue state=.active
// [1] error(libxev_kqueue): invalid state in submission queue state=.active
// [1] error(libxev_kqueue): invalid state in submission queue state=.active
// [1] error(libxev_kqueue): invalid state in submission queue state=.active
//
// and this make even less:
// Thread 14 Crashed:
// 0   libsystem_kernel.dylib               0x1996115b0 __pthread_kill + 8
// 1   libsystem_pthread.dylib              0x19964b888 pthread_kill + 296
// 2   libsystem_c.dylib                    0x199550850 abort + 124
// 3   libcore.dylib                        0x13ae0d268 posix.abort + 20
// 4   libcore.dylib                        0x13adf9f24 debug.defaultPanic + 136
// 5   libcore.dylib                        0x13ae08924 debug.FullPanic((function 'defaultPanic')).reachedUnreachable + 52
// 6   libcore.dylib                        0x13adfbef8 debug.assert + 56
// 7   libcore.dylib                        0x13af05314 queue.Intrusive(backend.kqueue.Completion).push + 56
// 8   libcore.dylib                        0x13af02db8 backend.kqueue.Loop.submit + 1924
// 9   libcore.dylib                        0x13af06ce4 backend.kqueue.Loop.tick + 352
// 10  libcore.dylib                        0x13af083d8 backend.kqueue.Loop.run + 268
// 11  libcore.dylib                        0x13af14600 monitor.Thread.threadMain_ + 168
// 12  libcore.dylib                        0x13af144bc monitor.Thread.threadMain + 60
// 13  libcore.dylib                        0x13af14470 Thread.callFn__anon_44102 + 32
// 14  libcore.dylib                        0x13af143f4 Thread.PosixThreadImpl.spawn__anon_44076.Instance.entryFn + 116
// 15  libsystem_pthread.dylib              0x19964bc08 _pthread_start + 136
// 16  libsystem_pthread.dylib              0x199646ba8 thread_start + 8
