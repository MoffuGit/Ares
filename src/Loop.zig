pub const Loop = @This();

const std = @import("std");
const xev = @import("global.zig").xev;
const vaxis = @import("vaxis");
const BlockingQueue = @import("datastruct/blocking_queue.zig").BlockingQueue;

const Allocator = std.mem.Allocator;

const App = @import("App.zig");
const Timer = @import("element/Timer.zig");
const AnimationMod = @import("element/Animation.zig");
const BaseAnimation = AnimationMod.BaseAnimation;
const TimeManager = @import("TimeManager.zig");

pub const TickCallback = *const fn (userdata: ?*anyopaque, time: i64) ?Tick;

pub const Tick = struct {
    next: i64,
    callback: TickCallback,
    userdata: ?*anyopaque = null,

    pub fn lessThan(_: void, a: Tick, b: Tick) std.math.Order {
        return std.math.order(a.next, b.next);
    }
};

pub const Message = union(enum) {
    resize: vaxis.Winsize,
    tick: Tick,
    timer_start: *Timer,
    timer_pause: u64,
    timer_resume: u64,
    timer_cancel: u64,
    animation_start: *BaseAnimation,
    animation_pause: u64,
    animation_resume: u64,
    animation_cancel: u64,
};

pub const Mailbox = BlockingQueue(Message, 64);

const log = std.log.scoped(.loop);

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

app: *App,

pub fn init(alloc: Allocator, app: *App) !Loop {
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
        .app = app,
        .tick_h = tick_h,
        .loop = loop,
        .stop = stop_h,
        .reschedule_tick = reschedule_tick_h,
        .mailbox = mailbox,
        .wakeup = wakeup_h,
    };
}

pub fn deinit(self: *Loop) void {
    self.stop.deinit();
    self.tick_h.deinit();
    self.wakeup.deinit();
    self.reschedule_tick.deinit();
    self.mailbox.destroy(self.alloc);
}

pub fn run(self: *Loop) void {
    self.run_() catch |err| {
        log.warn("error in loop err={}", .{err});
    };
}

pub fn run_(self: *Loop) !void {
    defer log.debug("loop exited", .{});

    self.wakeup.wait(&self.loop, &self.wakeup_c, Loop, self, wakeupCallback);
    self.reschedule_tick.wait(&self.loop, &self.reschedule_tick_c, Loop, self, rescheduleTickCallback);

    try self.wakeup.notify();

    log.debug("starting loop", .{});
    defer log.debug("starting loop shutdown", .{});
    _ = try self.loop.run(.until_done);
}

fn wakeupCallback(
    self_: ?*Loop,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Async.WaitError!void,
) xev.CallbackAction {
    _ = r catch |err| {
        log.err("error in wakeup err={}", .{err});
        return .rearm;
    };

    const l = self_.?;

    l.drainMailbox() catch |err|
        log.err("error draining mailbox err={}", .{err});

    l.app.draw() catch |err|
        log.err("draw error: {}", .{err});

    return .rearm;
}

fn rescheduleTickCallback(
    self_: ?*Loop,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Async.WaitError!void,
) xev.CallbackAction {
    _ = r catch |err| {
        log.err("error in reschedule_tick err={}", .{err});
        return .rearm;
    };

    const l = self_.?;
    l.scheduleNextTick();

    return .rearm;
}

pub fn scheduleNextTick(self: *Loop) void {
    const next_tick = self.app.time.peekNext() orelse {
        self.tick_armed = false;
        return;
    };

    const now = std.time.microTimestamp();
    const delay_us: u64 = @intCast(@max(0, next_tick.next - now));
    const delay_ms: u64 = (delay_us + 999) / 1000;
    const clamped_delay = @max(1, delay_ms);

    if (self.tick_armed) {
        self.tick_h.reset(&self.loop, &self.tick_c, &self.tick_cancel_c, clamped_delay, Loop, self, resetCallback);
    } else {
        self.tick_armed = true;
        self.tick_h.run(
            &self.loop,
            &self.tick_c,
            clamped_delay,
            Loop,
            self,
            tickCallback,
        );
    }
}

fn resetCallback(
    self_: ?*Loop,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Timer.RunError!void,
) xev.CallbackAction {
    const l: *Loop = self_ orelse return .disarm;

    if (r) |_| {
        const now = std.time.microTimestamp();
        l.app.time.processDue(now) catch |err| {
            log.err("tick error: {}", .{err});
        };
        l.tick_armed = false;
        l.scheduleNextTick();
    } else |_| {}

    return .disarm;
}

fn tickCallback(
    self_: ?*Loop,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Timer.RunError!void,
) xev.CallbackAction {
    _ = r catch {};
    const l: *Loop = self_ orelse {
        log.warn("tick callback fired without data set", .{});
        return .disarm;
    };

    l.tick_armed = false;

    const now = std.time.microTimestamp();
    l.app.time.processDue(now) catch |err| {
        log.err("tick error: {}", .{err});
    };

    l.scheduleNextTick();

    return .disarm;
}

fn drainMailbox(self: *Loop) !void {
    var needs_reschedule = false;

    while (self.mailbox.pop()) |message| {
        switch (message) {
            .resize => |size| {
                self.app.resize(size);
            },
            .tick => |tick| {
                if (try self.app.time.addTick(tick)) {
                    needs_reschedule = true;
                }
            },
            .timer_start => |timer| {
                if (try self.app.time.startTimer(timer)) {
                    needs_reschedule = true;
                }
            },
            .timer_pause => |id| {
                self.app.time.pauseTimer(id);
            },
            .timer_resume => |id| {
                if (try self.app.time.resumeTimer(id)) {
                    needs_reschedule = true;
                }
            },
            .timer_cancel => |id| {
                self.app.time.cancelTimer(id);
            },
            .animation_start => |animation| {
                if (try self.app.time.startAnimation(animation)) {
                    needs_reschedule = true;
                }
            },
            .animation_pause => |id| {
                self.app.time.pauseAnimation(id);
            },
            .animation_resume => |id| {
                if (try self.app.time.resumeAnimation(id)) {
                    needs_reschedule = true;
                }
            },
            .animation_cancel => |id| {
                self.app.time.cancelAnimation(id);
            },
        }
    }

    if (needs_reschedule) {
        self.scheduleNextTick();
    }
}
