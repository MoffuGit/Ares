const std = @import("std");
const Allocator = std.mem.Allocator;
const xev = @import("../global.zig").xev;
const BlockingQueue = @import("datastruct").BlockingQueue;
const messagepkg = @import("Message.zig");
const Monitor = @import("mod.zig");

const log = std.log.scoped(.monitor);

pub const Thread = @This();

const FLUSH_INTERVAL_MS = 150;

alloc: Allocator,
loop: xev.Loop,

monitor: *Monitor,

stop: xev.Async,
stop_c: xev.Completion = .{},

flush_timer: xev.Timer,
flush_timer_c: xev.Completion = .{},

pub fn init(alloc: Allocator, monitor: *Monitor) !Thread {
    var loop = try xev.Loop.init(.{});
    errdefer loop.deinit();

    var stop_h = try xev.Async.init();
    errdefer stop_h.deinit();

    var flush_timer = try xev.Timer.init();
    errdefer flush_timer.deinit();

    return .{
        .monitor = monitor,
        .alloc = alloc,
        .loop = loop,
        .stop = stop_h,
        .flush_timer = flush_timer,
    };
}

pub fn deinit(self: *Thread) void {
    self.flush_timer.deinit();
    self.stop.deinit();
    self.loop.deinit();
}

pub fn threadMain(self: *Thread) void {
    self.threadMain_() catch |err| {
        log.err("error in monitor thread err={}", .{err});
    };
}

fn threadMain_(self: *Thread) !void {
    defer log.debug("monitor thread exited", .{});

    self.stop.wait(&self.loop, &self.stop_c, Thread, self, stopCallback);
    self.scheduleFlushTimer();

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
    // self.monitor.flushPendingEvents();
    // self.monitor.cleanupCancelledWatchers();
    self.scheduleFlushTimer();
    return .disarm;
}
