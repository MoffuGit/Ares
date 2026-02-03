const std = @import("std");
const Allocator = std.mem.Allocator;
const xev = @import("../../global.zig").xev;
const BlockingQueue = @import("../../datastruct/blocking_queue.zig").BlockingQueue;
const messagepkg = @import("Message.zig");
const Monitor = @import("mod.zig");

const log = std.log.scoped(.worktree_monitor);

pub const Thread = @This();

pub const Mailbox = BlockingQueue(messagepkg.Message, 1024);

const NOTIFY_INTERVAL_MS = 100;

alloc: Allocator,
loop: xev.Loop,

mailbox: *Mailbox,

fs: xev.FileSystem,

monitor: *Monitor,

wakeup: xev.Async,
wakeup_c: xev.Completion = .{},

stop: xev.Async,
stop_c: xev.Completion = .{},

notify_timer: xev.Timer,
notify_timer_c: xev.Completion = .{},
has_pending_events: std.atomic.Value(bool) = .{ .raw = false },

pub fn init(alloc: Allocator, monitor: *Monitor) !Thread {
    var loop = try xev.Loop.init(.{});
    errdefer loop.deinit();

    var mailbox = try Mailbox.create(alloc);
    errdefer mailbox.destroy(alloc);

    var wakeup_h = try xev.Async.init();
    errdefer wakeup_h.deinit();

    var stop_h = try xev.Async.init();
    errdefer stop_h.deinit();

    var fs_h = xev.FileSystem.init();
    errdefer fs_h.deinit();

    var notify_timer = try xev.Timer.init();
    errdefer notify_timer.deinit();

    return .{
        .monitor = monitor,
        .alloc = alloc,
        .loop = loop,
        .mailbox = mailbox,
        .wakeup = wakeup_h,
        .stop = stop_h,
        .fs = fs_h,
        .notify_timer = notify_timer,
    };
}

pub fn deinit(self: *Thread) void {
    while (self.mailbox.pop()) |message| {
        switch (message) {
            .add => |data| {
                self.alloc.free(data.path);
            },
            .remove => {},
        }
    }

    self.notify_timer.deinit();
    self.fs.deinit();
    self.wakeup.deinit();
    self.stop.deinit();
    self.loop.deinit();
    self.mailbox.destroy(self.alloc);
}

pub fn threadMain(self: *Thread) void {
    self.threadMain_() catch |err| {
        log.err("error in worktree monitor thread err={}", .{err});
    };
}

fn threadMain_(self: *Thread) !void {
    defer log.debug("worktree monitor thread exited", .{});

    self.stop.wait(&self.loop, &self.stop_c, Thread, self, stopCallback);
    self.wakeup.wait(&self.loop, &self.wakeup_c, Thread, self, wakeupCallback);
    self.scheduleNotifyTimer();
    try self.fs.start(&self.loop);

    log.debug("starting worktree monitor thread", .{});
    defer log.debug("starting worktree monitor thread shutdown", .{});
    _ = try self.loop.run(.until_done);
}

fn scheduleNotifyTimer(self: *Thread) void {
    self.notify_timer.run(
        &self.loop,
        &self.notify_timer_c,
        NOTIFY_INTERVAL_MS,
        Thread,
        self,
        notifyTimerCallback,
    );
}

fn notifyTimerCallback(
    self_: ?*Thread,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Timer.RunError!void,
) xev.CallbackAction {
    _ = r catch |err| {
        log.err("notify timer error: {}", .{err});
        return .disarm;
    };

    const self = self_.?;

    if (self.has_pending_events.swap(false, .acquire)) {
        self.monitor.worktree.scanner_thread.wakeup.notify() catch |err| {
            log.err("error notifying scanner thread: {}", .{err});
        };
    }

    self.scheduleNotifyTimer();
    return .disarm;
}

fn stopCallback(
    self_: ?*Thread,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Async.WaitError!void,
) xev.CallbackAction {
    _ = r catch unreachable;
    self_.?.loop.stop();
    return .disarm;
}

fn fsEventsCallback(
    entry: ?*Monitor.WatcherEntry,
    _: *xev.FileSystem.Watcher,
    _: []const u8,
    events: u32,
) xev.CallbackAction {
    const e = entry orelse return .rearm;
    const thread = e.thread;

    _ = thread.monitor.worktree.scanner_thread.mailbox.push(.{ .fsEvent = .{ .id = e.id, .events = events } }, .instant);
    thread.has_pending_events.store(true, .release);

    return .rearm;
}

fn wakeupCallback(
    self_: ?*Thread,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Async.WaitError!void,
) xev.CallbackAction {
    _ = r catch |err| {
        log.err("error in worktree monitor wakeup err={}", .{err});
        return .rearm;
    };

    const s = self_.?;

    s.monitor.cleanupCancelledWatchers();

    s.drainMailbox() catch |err| {
        log.err("error draining monitor mailbox err={}", .{err});
    };

    return .rearm;
}

fn drainMailbox(self: *Thread) !void {
    while (self.mailbox.pop()) |message| {
        switch (message) {
            .add => |data| {
                try self.monitor.addWatcher(&self.fs, data.path, data.id, self, fsEventsCallback);
            },
            .remove => |id| {
                self.monitor.removeWatcher(&self.fs, id);
            },
        }
    }
}
