pub const Animation = @This();

const std = @import("std");
const Tick = @import("mod.zig").Tick;
const State = @import("mod.zig").State;
const TimerContext = @import("mod.zig").TimerContext;

pub const Callback = *const fn (userdata: ?*anyopaque, progress: f32) void;
pub const CompleteCallback = *const fn (userdata: ?*anyopaque) void;

id: u64 = 0,
duration_us: i64,
start_time: i64 = 0,
elapsed_at_pause: i64 = 0,
callback: Callback,
userdata: ?*anyopaque = null,
tick_interval_us: i64 = 16_667,
repeat: bool = false,
state: State = .idle,
context: ?TimerContext = null,
on_complete: ?CompleteCallback = null,

pub fn start(self: *Animation) void {
    if (self.context) |ctx| {
        _ = ctx.mailbox.push(.{ .animation_start = self }, .instant);
        ctx.wakeup.notify() catch {};
    }
}

pub fn pause(self: *Animation) void {
    if (self.context) |ctx| {
        _ = ctx.mailbox.push(.{ .animation_pause = self.id }, .instant);
        ctx.wakeup.notify() catch {};
    }
}

pub fn resume_(self: *Animation) void {
    if (self.context) |ctx| {
        _ = ctx.mailbox.push(.{ .animation_resume = self.id }, .instant);
        ctx.wakeup.notify() catch {};
    }
}

pub fn cancel(self: *Animation) void {
    if (self.context) |ctx| {
        _ = ctx.mailbox.push(.{ .animation_cancel = self.id }, .instant);
        ctx.wakeup.notify() catch {};
    }
}

pub fn toTick(self: *Animation) Tick {
    return .{
        .next = self.start_time + self.tick_interval_us,
        .callback = tickCallback,
        .userdata = @ptrCast(self),
    };
}

fn tickCallback(userdata: ?*anyopaque, time: i64) ?Tick {
    const anim: *Animation = @ptrCast(@alignCast(userdata orelse return null));

    switch (anim.state) {
        .idle, .cancelled, .completed => return null,
        .paused => {
            anim.elapsed_at_pause = time - anim.start_time;
            return null;
        },
        .active => {
            const elapsed = time - anim.start_time;
            const progress: f32 = @min(1.0, @as(f32, @floatFromInt(elapsed)) / @as(f32, @floatFromInt(anim.duration_us)));

            anim.callback(anim.userdata, progress);

            if (progress >= 1.0) {
                if (anim.repeat) {
                    anim.start_time = time;
                    return Tick{
                        .next = time + anim.tick_interval_us,
                        .callback = tickCallback,
                        .userdata = userdata,
                    };
                }
                anim.state = .completed;
                if (anim.on_complete) |cb| cb(anim.userdata);
                return null;
            }

            return Tick{
                .next = time + anim.tick_interval_us,
                .callback = tickCallback,
                .userdata = userdata,
            };
        },
    }
}
