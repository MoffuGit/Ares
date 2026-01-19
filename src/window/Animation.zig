const std = @import("std");
const Tick = @import("mod.zig").Tick;
const AnimState = @import("mod.zig").State;
const TimerContext = @import("mod.zig").TimerContext;
const Easing = @import("Easing.zig").Type;
const Element = @import("Element.zig");

pub const BaseAnimation = struct {
    id: u64 = 0,
    duration_us: i64,
    start_time: i64 = 0,
    elapsed_at_pause: i64 = 0,
    tick_interval_us: i64 = 16_667,
    easing: Easing = .linear,
    repeat: bool = false,
    anim_state: AnimState = .idle,
    context: ?TimerContext = null,

    tickFn: *const fn (self: *BaseAnimation, time: i64) ?Tick,

    pub fn toTick(self: *BaseAnimation) Tick {
        return .{
            .next = self.start_time + self.tick_interval_us,
            .callback = tickCallback,
            .userdata = @ptrCast(self),
        };
    }

    fn tickCallback(userdata: ?*anyopaque, time: i64) ?Tick {
        const self: *BaseAnimation = @ptrCast(@alignCast(userdata orelse return null));
        return self.tickFn(self, time);
    }
};

pub fn Animation(comptime State: type) type {
    return struct {
        const Self = @This();

        pub const UpdateFn = *const fn (start: State, end: State, progress: f32) State;
        pub const Callback = *const fn (userdata: ?*anyopaque, state: State, ctx: Element.Context) void;
        pub const CompleteCallback = *const fn (userdata: ?*anyopaque, ctx: Element.Context) void;

        base: BaseAnimation,

        start: State,
        end: State,
        current: State = undefined,

        updateFn: UpdateFn,
        callback: Callback,
        userdata: ?*anyopaque = null,
        on_complete: ?CompleteCallback = null,

        pub fn init(opts: struct {
            start: State,
            end: State,
            duration_us: i64,
            updateFn: UpdateFn,
            callback: Callback,
            userdata: ?*anyopaque = null,
            easing: Easing = .linear,
            repeat: bool = false,
            tick_interval_us: i64 = 16_667,
            on_complete: ?CompleteCallback = null,
        }) Self {
            return .{
                .base = .{
                    .duration_us = opts.duration_us,
                    .easing = opts.easing,
                    .repeat = opts.repeat,
                    .tick_interval_us = opts.tick_interval_us,
                    .tickFn = tickCallback,
                },
                .start = opts.start,
                .end = opts.end,
                .current = opts.start,
                .updateFn = opts.updateFn,
                .callback = opts.callback,
                .userdata = opts.userdata,
                .on_complete = opts.on_complete,
            };
        }

        pub fn toBase(self: *Self) *BaseAnimation {
            return &self.base;
        }

        pub fn startAnim(self: *Self) void {
            if (self.base.context) |ctx| {
                _ = ctx.mailbox.push(.{ .animation_start = &self.base }, .instant);
                ctx.wakeup.notify() catch {};
            }
        }

        pub fn pause(self: *Self) void {
            if (self.base.context) |ctx| {
                _ = ctx.mailbox.push(.{ .animation_pause = self.base.id }, .instant);
                ctx.wakeup.notify() catch {};
            }
        }

        pub fn resume_(self: *Self) void {
            if (self.base.context) |ctx| {
                _ = ctx.mailbox.push(.{ .animation_resume = self.base.id }, .instant);
                ctx.wakeup.notify() catch {};
            }
        }

        pub fn cancel(self: *Self) void {
            if (self.base.context) |ctx| {
                _ = ctx.mailbox.push(.{ .animation_cancel = self.base.id }, .instant);
                ctx.wakeup.notify() catch {};
            }
        }

        fn tickCallback(base: *BaseAnimation, time: i64) ?Tick {
            const self: *Self = @fieldParentPtr("base", base);
            const ctx = self.base.context orelse return null;

            switch (self.base.anim_state) {
                .idle, .cancelled, .completed => return null,
                .paused => {
                    self.base.elapsed_at_pause = time - self.base.start_time;
                    return null;
                },
                .active => {
                    const elapsed = time - self.base.start_time;
                    const t: f32 = @min(1.0, @as(f32, @floatFromInt(elapsed)) / @as(f32, @floatFromInt(self.base.duration_us)));
                    const progress = self.base.easing.apply(t);

                    self.current = self.updateFn(self.start, self.end, progress);

                    const element_ctx: Element.Context = .{
                        .mailbox = ctx.mailbox,
                        .wakeup = ctx.wakeup,
                        .needs_draw = ctx.needs_draw,
                    };
                    self.callback(self.userdata, self.current, element_ctx);

                    if (t >= 1.0) {
                        if (self.base.repeat) {
                            self.base.start_time = time;
                            return self.base.toTick();
                        }
                        self.base.anim_state = .completed;
                        if (self.on_complete) |cb| cb(self.userdata, element_ctx);
                        return null;
                    }

                    return self.base.toTick();
                },
            }
        }
    };
}
