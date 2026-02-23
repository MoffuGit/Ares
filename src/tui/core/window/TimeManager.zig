const std = @import("std");
const Allocator = std.mem.Allocator;

const message = @import("message.zig");
const Tick = message.Tick;
const AnimationMessage = message.AnimationMessage;
const TimerMessage = message.TimerMessage;

const Timer = @import("element/Timer.zig");
const AnimationMod = @import("element/Animation.zig");
const BaseAnimation = AnimationMod.BaseAnimation;

const Ticks = std.PriorityQueue(Tick, void, Tick.lessThan);

const TimeManager = @This();

timers: std.AutoHashMap(u64, *Timer),
animations: std.AutoHashMap(u64, *BaseAnimation),
next_id: u64 = 1,
ticks: Ticks,

pub fn init(alloc: Allocator) TimeManager {
    return .{
        .timers = std.AutoHashMap(u64, *Timer).init(alloc),
        .animations = std.AutoHashMap(u64, *BaseAnimation).init(alloc),
        .ticks = Ticks.init(alloc, {}),
    };
}

pub fn deinit(self: *TimeManager) void {
    self.ticks.deinit();
    self.animations.deinit();
    self.timers.deinit();
}

pub fn handleAnimation(self: *TimeManager, animation: AnimationMessage) !void {
    switch (animation) {
        .start => |a| try self.startAnimation(a),
        ._resume => |id| try self.resumeAnimation(id),
        .cancel => |id| self.cancelAnimation(id),
        .pause => |id| self.pauseAnimation(id),
    }
}

pub fn handleTimer(self: *TimeManager, timer: TimerMessage) !void {
    switch (timer) {
        .start => |t| try self.startTimer(t),
        ._resume => |id| try self.resumeTimer(id),
        .cancel => |id| self.cancelTimer(id),
        .pause => |id| self.pauseTimer(id),
    }
}

pub fn peekNext(self: *TimeManager) ?Tick {
    return self.ticks.peek();
}

pub fn addTick(self: *TimeManager, tick: Tick) !void {
    try self.ticks.add(tick);
}

pub fn processDue(self: *TimeManager, now: i64) !void {
    while (self.ticks.peek()) |peek| {
        if (peek.next > now) break;

        const tick = self.ticks.remove();
        if (tick.callback(tick.userdata, tick.next)) |new| {
            const clamped_next = if (new.next <= now) now + 1 else new.next;
            try self.ticks.add(.{
                .next = clamped_next,
                .callback = new.callback,
                .userdata = new.userdata,
            });
        } else {
            self.cleanupFromTick(tick);
        }
    }
}

fn cleanupFromTick(self: *TimeManager, tick: Tick) void {
    const userdata = tick.userdata orelse return;

    var it_timers = self.timers.iterator();
    while (it_timers.next()) |entry| {
        const timer: *Timer = entry.value_ptr.*;
        if (@intFromPtr(timer) == @intFromPtr(userdata)) {
            if (timer.state == .cancelled or timer.state == .completed) {
                _ = self.timers.remove(entry.key_ptr.*);
            }
            return;
        }
    }

    var it_anims = self.animations.iterator();
    while (it_anims.next()) |entry| {
        const anim: *BaseAnimation = entry.value_ptr.*;
        if (@intFromPtr(anim) == @intFromPtr(userdata)) {
            if (anim.anim_state == .cancelled or anim.anim_state == .completed) {
                _ = self.animations.remove(entry.key_ptr.*);
            }
            return;
        }
    }
}

fn registerTimer(self: *TimeManager, timer: *Timer) !void {
    timer.id = self.next_id;
    self.next_id += 1;
    try self.timers.put(timer.id, timer);
}

pub fn startTimer(self: *TimeManager, timer: *Timer) !void {
    if (timer.id == 0) {
        try self.registerTimer(timer);
    }
    timer.state = .active;
    try self.addTick(timer.toTick());
}

pub fn pauseTimer(self: *TimeManager, id: u64) void {
    if (self.timers.get(id)) |timer| {
        if (timer.state == .active) {
            timer.state = .paused;
        }
    }
}

pub fn resumeTimer(self: *TimeManager, id: u64) !void {
    if (self.timers.get(id)) |timer| {
        if (timer.state == .paused) {
            timer.state = .active;
            try self.addTick(timer.toTick());
        }
    }
}

pub fn cancelTimer(self: *TimeManager, id: u64) void {
    if (self.timers.get(id)) |timer| {
        timer.state = .cancelled;
    }
}

fn registerAnimation(self: *TimeManager, animation: *BaseAnimation) !void {
    animation.id = self.next_id;
    self.next_id += 1;
    try self.animations.put(animation.id, animation);
}

pub fn startAnimation(self: *TimeManager, animation: *BaseAnimation) !void {
    if (animation.id == 0) {
        try self.registerAnimation(animation);
    }
    animation.anim_state = .active;
    animation.start_time = std.time.microTimestamp();
    animation.elapsed_at_pause = 0;
    try self.addTick(animation.toTick());
}

pub fn pauseAnimation(self: *TimeManager, id: u64) void {
    if (self.animations.get(id)) |animation| {
        if (animation.anim_state == .active) {
            animation.anim_state = .paused;
        }
    }
}

pub fn resumeAnimation(self: *TimeManager, id: u64) !void {
    if (self.animations.get(id)) |animation| {
        if (animation.anim_state == .paused) {
            const now = std.time.microTimestamp();
            animation.start_time = now - animation.elapsed_at_pause;
            animation.anim_state = .active;
            try self.addTick(animation.toTick());
        }
    }
}

pub fn cancelAnimation(self: *TimeManager, id: u64) void {
    if (self.animations.get(id)) |animation| {
        animation.anim_state = .cancelled;
    }
}
