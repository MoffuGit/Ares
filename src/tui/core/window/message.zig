const std = @import("std");
const vaxis = @import("vaxis");

const Timer = @import("element/Timer.zig");
const AnimationMod = @import("element/Animation.zig");
const BaseAnimation = AnimationMod.BaseAnimation;
const Event = @import("event.zig").Event;

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
};
