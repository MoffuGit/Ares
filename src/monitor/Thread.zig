const std = @import("std");
const Allocator = std.mem.Allocator;
const xev = @import("../global.zig").xev;
const BlockingQueue = @import("datastruct").BlockingQueue;
const messagepkg = @import("Message.zig");
const Monitor = @import("mod.zig");

const log = std.log.scoped(.monitor);

pub const Thread = @This();

pub const Mailbox = BlockingQueue(messagepkg.Message, 1024);

const FLUSH_INTERVAL_MS = 100;

alloc: Allocator,
loop: xev.Loop,

mailbox: *Mailbox,

fs: xev.FileSystem,

monitor: *Monitor,

wakeup: xev.Async,
wakeup_c: xev.Completion = .{},

stop: xev.Async,
stop_c: xev.Completion = .{},

flush_timer: xev.Timer,
flush_timer_c: xev.Completion = .{},

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

    var flush_timer = try xev.Timer.init();
    errdefer flush_timer.deinit();

    return .{
        .monitor = monitor,
        .alloc = alloc,
        .loop = loop,
        .mailbox = mailbox,
        .wakeup = wakeup_h,
        .stop = stop_h,
        .fs = fs_h,
        .flush_timer = flush_timer,
    };
}

pub fn deinit(self: *Thread) void {
    while (self.mailbox.pop()) |message| {
        switch (message) {
            .add => |req| {
                req.alloc.free(req.path);
                req.alloc.destroy(req);
            },
            .remove => {},
        }
    }

    self.flush_timer.deinit();
    self.fs.deinit();
    self.wakeup.deinit();
    self.stop.deinit();
    self.loop.deinit();
    self.mailbox.destroy(self.alloc);
}

pub fn threadMain(self: *Thread) void {
    self.threadMain_() catch |err| {
        log.err("error in monitor thread err={}", .{err});
    };
}

fn threadMain_(self: *Thread) !void {
    defer log.debug("monitor thread exited", .{});

    self.stop.wait(&self.loop, &self.stop_c, Thread, self, stopCallback);
    self.wakeup.wait(&self.loop, &self.wakeup_c, Thread, self, wakeupCallback);
    self.scheduleFlushTimer();
    try self.fs.start(&self.loop);

    log.debug("starting monitor thread", .{});
    defer log.debug("starting monitor thread shutdown", .{});
    _ = try self.loop.run(.until_done);
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

fn scheduleFlushTimer(self: *Thread) void {
    self.flush_timer.run(
        &self.loop,
        &self.flush_timer_c,
        FLUSH_INTERVAL_MS,
        Thread,
        self,
        flushTimerCallback,
    );
}

fn flushTimerCallback(
    self_: ?*Thread,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Timer.RunError!void,
) xev.CallbackAction {
    _ = r catch |err| {
        log.err("flush timer error: {}", .{err});
        return .disarm;
    };

    const self = self_.?;
    self.monitor.flushPendingEvents();
    self.monitor.cleanupCancelledWatchers();
    self.scheduleFlushTimer();
    return .disarm;
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

fn wakeupCallback(
    self_: ?*Thread,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Async.WaitError!void,
) xev.CallbackAction {
    _ = r catch |err| {
        log.err("error in monitor wakeup err={}", .{err});
        return .rearm;
    };

    const s = self_.?;

    s.drainMailbox();

    return .rearm;
}

fn drainMailbox(self: *Thread) void {
    while (self.mailbox.pop()) |message| {
        switch (message) {
            .add => |req| {
                self.monitor.addWatcher(&self.fs, req, fsEventsCallback);
            },
            .remove => |id| {
                self.monitor.removeWatcher(&self.fs, id);
            },
        }
    }
}
