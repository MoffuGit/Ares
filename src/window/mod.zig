pub const Window = @This();

const std = @import("std");
const vaxis = @import("vaxis");
const xev = @import("../global.zig").xev;
const Allocator = std.mem.Allocator;
const SharedState = @import("../SharedState.zig");
const Buffer = @import("../Buffer.zig");
const Element = @import("Element.zig");

const RendererMailbox = @import("../renderer/Thread.zig").Mailbox;
const WindowMailbox = @import("Thread.zig").Mailbox;

pub const Timer = @import("Timer.zig");
pub const Animation = @import("Animation.zig");
pub const Easing = @import("Easing.zig").Type;

pub const TickCallback = *const fn (userdata: ?*anyopaque, time: i64) ?Tick;

pub const Tick = struct {
    next: i64,
    callback: TickCallback,
    userdata: ?*anyopaque = null,

    pub fn lessThan(_: void, a: Tick, b: Tick) std.math.Order {
        return std.math.order(a.next, b.next);
    }
};

const Ticks = std.PriorityQueue(Tick, void, Tick.lessThan);

pub const State = enum {
    idle,
    active,
    paused,
    cancelled,
    completed,
};

pub const TimerContext = struct {
    mailbox: *WindowMailbox,
    wakeup: xev.Async,
    needs_draw: *bool,
};

pub const Opts = struct {
    render_wakeup: xev.Async,
    render_mailbox: *RendererMailbox,
    shared_state: *SharedState,
    window_mailbox: *WindowMailbox,
    window_wakeup: xev.Async,
    reschedule_tick: xev.Async,
    root: *Element,
};

alloc: Allocator,

render_wakeup: xev.Async,
render_mailbox: *RendererMailbox,

shared_state: *SharedState,
buffer: Buffer,

ticks: Ticks,
timers: std.AutoHashMap(u64, *Timer),
animations: std.AutoHashMap(u64, *Animation),
next_id: u64 = 1,

root: *Element,

window_mailbox: *WindowMailbox,
window_wakeup: xev.Async,
reschedule_tick: xev.Async,

needs_draw: bool = true,

size: vaxis.Winsize,

pub fn init(alloc: Allocator, opts: Opts) !Window {
    var buffer = try Buffer.init(alloc, 0, 0);
    errdefer buffer.deinit(alloc);

    var ticks = Ticks.init(alloc, {});
    errdefer ticks.deinit();

    var timers = std.AutoHashMap(u64, *Timer).init(alloc);
    errdefer timers.deinit();

    var animations = std.AutoHashMap(u64, *Animation).init(alloc);
    errdefer animations.deinit();

    return .{
        .root = opts.root,
        .ticks = ticks,
        .timers = timers,
        .animations = animations,
        .alloc = alloc,
        .buffer = buffer,
        .render_wakeup = opts.render_wakeup,
        .render_mailbox = opts.render_mailbox,
        .shared_state = opts.shared_state,
        .window_mailbox = opts.window_mailbox,
        .window_wakeup = opts.window_wakeup,
        .reschedule_tick = opts.reschedule_tick,
        .size = .{
            .cols = 0,
            .rows = 0,
            .x_pixel = 0,
            .y_pixel = 0,
        },
    };
}

pub fn setup(self: *Window) void {
    const ctx: Element.Context = .{
        .mailbox = self.window_mailbox,
        .wakeup = self.window_wakeup,
        .needs_draw = &self.needs_draw,
    };
    self.root.setup(ctx);
}

pub fn deinit(self: *Window) void {
    self.buffer.deinit(self.alloc);
    self.ticks.deinit();
    self.timers.deinit();
    self.animations.deinit();
}

pub fn draw(self: *Window) !void {
    if (!self.needs_draw) return;
    self.needs_draw = false;

    var root = self.root;

    try root.update();
    root.draw(&self.buffer);

    const shared_state = self.shared_state;
    const write_screen = shared_state.writeBuffer();

    if (write_screen.width != self.buffer.width or write_screen.height != self.buffer.height) {
        try shared_state.resizeWriteBuffer(self.alloc, self.size);
    }

    @memcpy(write_screen.buf, self.buffer.buf);
    shared_state.swapWrite();

    try self.render_wakeup.notify();
}

pub fn processTicks(self: *Window) !void {
    const now = std.time.microTimestamp();
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
        }
    }
}

pub fn addTick(self: *Window, tick: Tick) !void {
    const was_empty = self.ticks.count() == 0;
    const old_min = self.ticks.peek();

    try self.ticks.add(tick);

    if (was_empty or (old_min != null and tick.next < old_min.?.next)) {
        try self.reschedule_tick.notify();
    }
}

pub fn registerTimer(self: *Window, timer: *Timer) !void {
    timer.id = self.next_id;
    self.next_id += 1;
    try self.timers.put(timer.id, timer);
}

pub fn unregisterTimer(self: *Window, id: u64) void {
    _ = self.timers.remove(id);
}

pub fn registerAnimation(self: *Window, animation: *Animation) !void {
    animation.id = self.next_id;
    self.next_id += 1;
    try self.animations.put(animation.id, animation);
}

pub fn unregisterAnimation(self: *Window, id: u64) void {
    _ = self.animations.remove(id);
}

pub fn startTimer(self: *Window, timer: *Timer) !void {
    if (timer.id == 0) {
        try self.registerTimer(timer);
    }
    timer.state = .active;
    try self.addTick(timer.toTick());
}

pub fn pauseTimer(self: *Window, id: u64) void {
    if (self.timers.get(id)) |timer| {
        if (timer.state == .active) {
            timer.state = .paused;
        }
    }
}

pub fn resumeTimer(self: *Window, id: u64) !void {
    if (self.timers.get(id)) |timer| {
        if (timer.state == .paused) {
            timer.state = .active;
            try self.addTick(timer.toTick());
        }
    }
}

pub fn cancelTimer(self: *Window, id: u64) void {
    if (self.timers.get(id)) |timer| {
        timer.state = .cancelled;
        self.unregisterTimer(id);
    }
}

pub fn startAnimation(self: *Window, animation: *Animation) !void {
    if (animation.id == 0) {
        try self.registerAnimation(animation);
    }
    animation.state = .active;
    animation.start_time = std.time.microTimestamp();
    animation.elapsed_at_pause = 0;
    try self.addTick(animation.toTick());
}

pub fn pauseAnimation(self: *Window, id: u64) void {
    if (self.animations.get(id)) |animation| {
        if (animation.state == .active) {
            animation.state = .paused;
        }
    }
}

pub fn resumeAnimation(self: *Window, id: u64) !void {
    if (self.animations.get(id)) |animation| {
        if (animation.state == .paused) {
            const now = std.time.microTimestamp();
            animation.start_time = now - animation.elapsed_at_pause;
            animation.state = .active;
            try self.addTick(animation.toTick());
        }
    }
}

pub fn cancelAnimation(self: *Window, id: u64) void {
    if (self.animations.get(id)) |animation| {
        animation.state = .cancelled;
        self.unregisterAnimation(id);
    }
}

pub fn resize(self: *Window, size: vaxis.Winsize) !void {
    if (self.size.rows == size.rows and self.size.cols == size.cols) return;

    self.size = size;

    self.buffer.deinit(self.alloc);
    self.buffer = try Buffer.init(self.alloc, self.size.cols, self.size.rows);

    self.needs_draw = true;
}
