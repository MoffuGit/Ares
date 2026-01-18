pub const Timer = @This();

const std = @import("std");
const Tick = @import("mod.zig").Tick;
const State = @import("mod.zig").State;
const TimerContext = @import("mod.zig").TimerContext;

const Element = @import("Element.zig");

pub const Callback = *const fn (userdata: ?*anyopaque, ctx: Element.Context) void;
pub const CompleteCallback = *const fn (userdata: ?*anyopaque, ctx: Element.Context) void;

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
context: ?TimerContext = null,
on_complete: ?CompleteCallback = null,

pub fn start(self: *Timer) void {
    if (self.context) |ctx| {
        _ = ctx.mailbox.push(.{ .timer_start = self }, .instant);
        ctx.wakeup.notify() catch {};
    }
}

pub fn pause(self: *Timer) void {
    if (self.context) |ctx| {
        _ = ctx.mailbox.push(.{ .timer_pause = self.id }, .instant);
        ctx.wakeup.notify() catch {};
    }
}

pub fn resume_(self: *Timer) void {
    if (self.context) |ctx| {
        _ = ctx.mailbox.push(.{ .timer_resume = self.id }, .instant);
        ctx.wakeup.notify() catch {};
    }
}

pub fn cancel(self: *Timer) void {
    if (self.context) |ctx| {
        _ = ctx.mailbox.push(.{ .timer_cancel = self.id }, .instant);
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
            const element_ctx: Element.Context = .{
                .mailbox = ctx.mailbox,
                .wakeup = ctx.wakeup,
                .needs_draw = ctx.needs_draw,
            };
            timer.callback(timer.userdata, element_ctx);

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
                        if (timer.on_complete) |cb| cb(timer.userdata, element_ctx);
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
