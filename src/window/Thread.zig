pub const Thread = @This();

const std = @import("std");
const xev = @import("../global.zig").xev;
const vaxis = @import("vaxis");
const BlockingQueue = @import("../datastruct/blocking_queue.zig").BlockingQueue;

const Allocator = std.mem.Allocator;

const Window = @import("mod.zig");
const Tick = Window.Tick;
const Timer = Window.Timer;
const Animation = Window.Animation;

pub const Message = union(enum) {
    resize: vaxis.Winsize,
    tick: Tick,
    timer_start: *Timer,
    timer_pause: u64,
    timer_resume: u64,
    timer_cancel: u64,
    animation_start: *Animation,
    animation_pause: u64,
    animation_resume: u64,
    animation_cancel: u64,
};

pub const Mailbox = BlockingQueue(Message, 64);

const log = std.log.scoped(.window_thread);

alloc: Allocator,

loop: xev.Loop,

wakeup: xev.Async,
wakeup_c: xev.Completion = .{},

stop: xev.Async,
stop_c: xev.Completion = .{},

reschedule_tick: xev.Async,
reschedule_tick_c: xev.Completion = .{},

tick_h: xev.Timer,
tick_c: xev.Completion = .{},
tick_cancel_c: xev.Completion = .{},
tick_armed: bool = false,

mailbox: *Mailbox,

window: *Window,

pub fn init(alloc: Allocator, window: *Window) !Thread {
    var loop = try xev.Loop.init(.{});
    errdefer loop.deinit();

    var wakeup_h = try xev.Async.init();
    errdefer wakeup_h.deinit();

    var stop_h = try xev.Async.init();
    errdefer stop_h.deinit();

    var reschedule_tick_h = try xev.Async.init();
    errdefer reschedule_tick_h.deinit();

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
        .reschedule_tick = reschedule_tick_h,
        .mailbox = mailbox,
        .wakeup = wakeup_h,
    };
}

pub fn deinit(self: *Thread) void {
    self.stop.deinit();
    self.tick_h.deinit();
    self.wakeup.deinit();
    self.reschedule_tick.deinit();
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
    self.reschedule_tick.wait(&self.loop, &self.reschedule_tick_c, Thread, self, rescheduleTickCallback);

    try self.wakeup.notify();

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

fn rescheduleTickCallback(
    self_: ?*Thread,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Async.WaitError!void,
) xev.CallbackAction {
    _ = r catch |err| {
        log.err("error in reschedule_tick err={}", .{err});
        return .rearm;
    };

    const t = self_.?;
    t.scheduleNextTick();

    return .rearm;
}

pub fn scheduleNextTick(self: *Thread) void {
    const next_tick = self.window.ticks.peek() orelse {
        self.tick_armed = false;
        return;
    };

    const now = std.time.microTimestamp();
    const delay_us: u64 = @intCast(@max(0, next_tick.next - now));
    const delay_ms: u64 = (delay_us + 999) / 1000;
    const clamped_delay = @max(1, delay_ms);

    if (self.tick_armed) {
        self.tick_h.reset(&self.loop, &self.tick_c, &self.tick_cancel_c, clamped_delay, Thread, self, resetCallback);
    } else {
        self.tick_armed = true;
        self.tick_h.run(
            &self.loop,
            &self.tick_c,
            clamped_delay,
            Thread,
            self,
            tickCallback,
        );
    }
}

fn resetCallback(
    self_: ?*Thread,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Timer.RunError!void,
) xev.CallbackAction {
    const t: *Thread = self_ orelse return .disarm;

    if (r) |_| {
        t.window.processTicks() catch |err| {
            log.err("window tick error: {}", .{err});
        };
        t.tick_armed = false;
        t.scheduleNextTick();
    } else |_| {}

    return .disarm;
}

fn tickCallback(
    self_: ?*Thread,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Timer.RunError!void,
) xev.CallbackAction {
    _ = r catch {};
    const t: *Thread = self_ orelse {
        log.warn("render callback fired without data set", .{});
        return .disarm;
    };

    t.tick_armed = false;

    t.window.processTicks() catch |err| {
        log.err("window tick error: {}", .{err});
    };

    t.scheduleNextTick();

    return .disarm;
}

fn drainMailbox(self: *Thread) !void {
    while (self.mailbox.pop()) |message| {
        switch (message) {
            .resize => |size| {
                try self.window.resize(size);
            },
            .tick => |tick| {
                try self.window.addTick(tick);
            },
            .timer_start => |timer| {
                try self.window.startTimer(timer);
                self.scheduleNextTick();
            },
            .timer_pause => |id| {
                self.window.pauseTimer(id);
            },
            .timer_resume => |id| {
                try self.window.resumeTimer(id);
                self.scheduleNextTick();
            },
            .timer_cancel => |id| {
                self.window.cancelTimer(id);
            },
            .animation_start => |animation| {
                try self.window.startAnimation(animation);
                self.scheduleNextTick();
            },
            .animation_pause => |id| {
                self.window.pauseAnimation(id);
            },
            .animation_resume => |id| {
                try self.window.resumeAnimation(id);
                self.scheduleNextTick();
            },
            .animation_cancel => |id| {
                self.window.cancelAnimation(id);
            },
        }
    }
}
