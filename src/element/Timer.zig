pub const Timer = @This();

const std = @import("std");
const Loop = @import("../Loop.zig");
const Tick = Loop.Tick;

const AppContext = @import("../AppContext.zig");

pub const State = enum {
    idle,
    active,
    paused,
    cancelled,
    completed,
};

pub const Callback = *const fn (userdata: ?*anyopaque, ctx: *AppContext) void;
pub const CompleteCallback = *const fn (userdata: ?*anyopaque, ctx: *AppContext) void;

pub const Repeat = union(enum) {
    forever,
    times: u32,
};

id: u64 = 0,
interval_us: i64,
callback: Callback,
userdata: ?*anyopaque = null,
repeat: Repeat = .forever,
state: State = .idle,
context: ?*AppContext = null,
on_complete: ?CompleteCallback = null,

pub fn start(self: *Timer) void {
    if (self.context) |ctx| {
        _ = ctx.mailbox.push(.{ .timer = .{ .start = self } }, .instant);
        ctx.wakeup.notify() catch {};
    }
}

pub fn pause(self: *Timer) void {
    if (self.context) |ctx| {
        _ = ctx.mailbox.push(.{ .timer = .{ .pause = self.id } }, .instant);
        ctx.wakeup.notify() catch {};
    }
}

pub fn resume_(self: *Timer) void {
    if (self.context) |ctx| {
        _ = ctx.mailbox.push(.{ .timer = .{ ._resume = self.id } }, .instant);
        ctx.wakeup.notify() catch {};
    }
}

pub fn cancel(self: *Timer) void {
    if (self.context) |ctx| {
        _ = ctx.mailbox.push(.{ .timer = .{ .cancel = self.id } }, .instant);
        ctx.wakeup.notify() catch {};
    }
}

pub fn toTick(self: *Timer) Tick {
    return .{
        .next = std.time.microTimestamp() + self.interval_us,
        .callback = tickCallback,
        .userdata = @ptrCast(self),
    };
}

fn tickCallback(userdata: ?*anyopaque, _: i64) ?Tick {
    const timer: *Timer = @ptrCast(@alignCast(userdata orelse return null));
    const ctx = timer.context orelse return null;

    switch (timer.state) {
        .idle, .cancelled, .completed => return null,
        .paused => return null,
        .active => {
            timer.callback(timer.userdata, ctx);

            switch (timer.repeat) {
                .forever => {
                    return Tick{
                        .next = std.time.microTimestamp() + timer.interval_us,
                        .callback = tickCallback,
                        .userdata = userdata,
                    };
                },
                .times => |*count| {
                    if (count.* <= 1) {
                        timer.state = .completed;
                        if (timer.on_complete) |cb| cb(timer.userdata, ctx);
                        return null;
                    }
                    count.* -= 1;
                    return Tick{
                        .next = std.time.microTimestamp() + timer.interval_us,
                        .callback = tickCallback,
                        .userdata = userdata,
                    };
                },
            }
        },
    }
}
