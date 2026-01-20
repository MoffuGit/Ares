const std = @import("std");
const xev = @import("global.zig").xev;
const Loop = @import("Loop.zig");
const Mailbox = Loop.Mailbox;
const Tick = Loop.Tick;

const Timer = @import("element/Timer.zig");
const AnimationMod = @import("element/Animation.zig");
const BaseAnimation = AnimationMod.BaseAnimation;

const AppContext = @This();

userdata: ?*anyopaque,
mailbox: *Mailbox,
wakeup: xev.Async,
stop: xev.Async,
needs_draw: *std.atomic.Value(bool),

pub fn addTick(self: *AppContext, tick: Tick) void {
    _ = self.mailbox.push(.{ .tick = tick }, .instant);
    self.wakeup.notify() catch {};
}

pub fn startTimer(self: *AppContext, timer: *Timer) void {
    timer.context = self;
    _ = self.mailbox.push(.{ .timer = .{ .start = timer } }, .instant);
    self.wakeup.notify() catch {};
}

pub fn startAnimation(self: *AppContext, animation: *BaseAnimation) void {
    animation.context = self;
    _ = self.mailbox.push(.{ .animation = .{ .start = animation } }, .instant);
    self.wakeup.notify() catch {};
}

pub fn requestDraw(self: *AppContext) void {
    if (self.needs_draw.load(.acquire)) return;
    self.needs_draw.store(true, .release);
    self.wakeup.notify() catch {};
}

pub fn stopApp(self: *AppContext) !void {
    try self.stop.notify();
}
