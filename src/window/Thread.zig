pub const Thread = @This();

const std = @import("std");
const xev = @import("../global.zig").xev;
const vaxis = @import("vaxis");
const BlockingQueue = @import("../datastruct/blocking_queue.zig").BlockingQueue;

const Allocator = std.mem.Allocator;

const Window = @import("mod.zig");
const Timer = @import("mod.zig").Timer;

pub const Message = union(enum) {
    resize: vaxis.Winsize,
    timer: Timer,
};

pub const Mailbox = BlockingQueue(Message, 64);

const log = std.log.scoped(.window_thread);

const TICK_INTERVAL = 8;

alloc: Allocator,

loop: xev.Loop,

wakeup: xev.Async,
wakeup_c: xev.Completion = .{},

stop: xev.Async,
stop_c: xev.Completion = .{},

tick_h: xev.Timer,
tick_c: xev.Completion = .{},

mailbox: *Mailbox,

window: *Window,

pub fn init(alloc: Allocator, window: *Window) !Thread {
    var loop = try xev.Loop.init(.{});
    errdefer loop.deinit();

    var wakeup_h = try xev.Async.init();
    errdefer wakeup_h.deinit();

    var stop_h = try xev.Async.init();
    errdefer stop_h.deinit();

    var tick_h = try xev.Timer.init();
    errdefer tick_h.deinit();

    var mailbox = try Mailbox.create(alloc);
    errdefer mailbox.destroy(alloc);

    return .{
        .alloc = alloc,
        .window = window,
        .tick_h = tick_h,
        .loop = loop,
        .stop = stop_h,
        .mailbox = mailbox,
        .wakeup = wakeup_h,
    };
}

pub fn deinit(self: *Thread) void {
    self.stop.deinit();
    self.tick_h.deinit();
    self.wakeup.deinit();
    self.mailbox.destroy(self.alloc);
}

pub fn threadMain(self: *Thread) void {
    self.threadMain_() catch |err| {
        log.warn("error in window err={}", .{err});
    };
}

fn threadMain_(self: *Thread) !void {
    defer log.debug("window thread exited", .{});

    self.wakeup.wait(&self.loop, &self.wakeup_c, Thread, self, wakeupCallback);

    try self.wakeup.notify();
    self.startTickTimer();

    log.debug("starting window thread", .{});
    defer log.debug("starting window thread shutdown", .{});
    _ = try self.loop.run(.until_done);
}

fn wakeupCallback(
    self_: ?*Thread,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Async.WaitError!void,
) xev.CallbackAction {
    _ = r catch |err| {
        log.err("error in wakeup err={}", .{err});
        return .rearm;
    };

    const t = self_.?;

    // When we wake up, we check the mailbox. Mailbox producers should
    // wake up our thread after publishing.
    t.drainMailbox() catch |err|
        log.err("error draining mailbox err={}", .{err});

    t.window.draw() catch |err|
        log.err("draw error: {}", .{err});

    return .rearm;
}

fn startTickTimer(self: *Thread) void {
    self.tick_h.run(
        &self.loop,
        &self.tick_c,
        TICK_INTERVAL,
        Thread,
        self,
        tickCallback,
    );
}

fn tickCallback(
    self_: ?*Thread,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Timer.RunError!void,
) xev.CallbackAction {
    _ = r catch unreachable;
    const t: *Thread = self_ orelse {
        // This shouldn't happen so we log it.
        log.warn("render callback fired without data set", .{});
        return .disarm;
    };

    t.window.tick() catch |err| {
        log.err("window tick error: {}", .{err});
    };

    t.tick_h.run(&t.loop, &t.tick_c, TICK_INTERVAL, Thread, t, tickCallback);

    return .disarm;
}

fn drainMailbox(self: *Thread) !void {
    while (self.mailbox.pop()) |message| {
        switch (message) {
            .resize => |size| {
                try self.window.resize(size);
            },
            .timer => |timer| {
                try self.window.timers.add(timer);
            },
        }
    }
}
