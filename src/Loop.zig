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
const Event = @import("events/Event.zig").Event;

pub const TickCallback = *const fn (userdata: ?*anyopaque, time: i64) ?Tick;

pub const Tick = struct {
    next: i64,
    callback: TickCallback,
    userdata: ?*anyopaque = null,

    pub fn lessThan(_: void, a: Tick, b: Tick) std.math.Order {
        return std.math.order(a.next, b.next);
    }
};

pub const TimerMessage = union(enum) {
    start: *Timer,
    pause: u64,
    _resume: u64,
    cancel: u64,
};

pub const AnimationMessage = union(enum) {
    start: *BaseAnimation,
    pause: u64,
    _resume: u64,
    cancel: u64,
};

pub const Message = union(enum) {
    resize: vaxis.Winsize,
    tick: Tick,
    timer: TimerMessage,
    animation: AnimationMessage,
    event: Event,
    scheme: App.Scheme,
};

pub const Mailbox = BlockingQueue(Message, 64);

const log = std.log.scoped(.loop);

alloc: Allocator,

loop: xev.Loop,

wakeup: xev.Async,
wakeup_c: xev.Completion = .{},

stop: xev.Async,
stop_c: xev.Completion = .{},

tick_h: xev.Timer,
tick_c: xev.Completion = .{},
tick_active: bool = false,

mailbox: *Mailbox,

app: *App,

pub fn init(alloc: Allocator, app: *App) !Loop {
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
        .app = app,
        .tick_h = tick_h,
        .loop = loop,
        .stop = stop_h,
        .mailbox = mailbox,
        .wakeup = wakeup_h,
    };
}

pub fn deinit(self: *Loop) void {
    self.stop.deinit();
    self.tick_h.deinit();
    self.wakeup.deinit();
    self.mailbox.destroy(self.alloc);
    self.loop.deinit();
}

pub fn run(self: *Loop) void {
    self.run_() catch |err| {
        log.warn("error in loop err={}", .{err});
    };
}

pub fn run_(self: *Loop) !void {
    defer log.debug("loop exited", .{});

    self.wakeup.wait(&self.loop, &self.wakeup_c, Loop, self, wakeupCallback);
    self.stop.wait(&self.loop, &self.stop_c, Loop, self, stopCallback);

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

pub fn scheduleNextTick(self: *Loop) void {
    if (self.app.time.peekNext() == null) {
        self.tick_active = false;
        return;
    }

    self.tick_active = true;

    self.tick_h.run(
        &self.loop,
        &self.tick_c,
        6,
        Loop,
        self,
        tickCallback,
    );
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

    l.tick_active = false;

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
            .scheme => |scheme| {
                //HACK:
                if (self.app.scheme == scheme) continue;
                try self.app.setScheme(scheme);
            },
            .resize => |size| {
                self.app.resize(size);
            },
            .tick => |tick| {
                if (try self.app.time.addTick(tick)) {
                    needs_reschedule = true;
                }
            },
            .animation => |animation| {
                if (try self.app.time.handleAnimation(animation)) {
                    needs_reschedule = true;
                }
            },
            .timer => |timer| {
                if (try self.app.time.handleTimer(timer)) {
                    needs_reschedule = true;
                }
            },
            .event => |evt| {
                try self.app.window.handleEvent(evt);
            },
        }
    }

    if (needs_reschedule) {
        self.scheduleNextTick();
    }
}

fn stopCallback(
    self_: ?*Loop,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Async.WaitError!void,
) xev.CallbackAction {
    _ = r catch unreachable;
    self_.?.loop.stop();
    return .disarm;
}
