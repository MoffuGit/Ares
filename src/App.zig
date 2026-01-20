const std = @import("std");
const vaxis = @import("vaxis");
const builtin = @import("builtin");
const posix = std.posix;

const Screen = @import("Screen.zig");

const RendererThread = @import("renderer/Thread.zig");
const Renderer = @import("renderer/mod.zig");

const Loop = @import("Loop.zig");
const Tick = Loop.Tick;

const EventsThread = @import("events/Thread.zig");

const Element = @import("element/Element.zig");
const Root = @import("element/Root.zig");
const Timer = @import("element/Timer.zig");
const AnimationMod = @import("element/Animation.zig");
const BaseAnimation = AnimationMod.BaseAnimation;

const log = std.log.scoped(.app);

const Allocator = std.mem.Allocator;

const Ticks = std.PriorityQueue(Tick, void, Tick.lessThan);

pub const State = enum {
    idle,
    active,
    paused,
    cancelled,
    completed,
};

const App = @This();

var tty_buffer: [1024]u8 = undefined;

alloc: Allocator,
tty: vaxis.Tty,

events_thread: EventsThread,
events_thr: std.Thread,

screen: Screen,
renderer: Renderer,
renderer_thread: RendererThread,
renderer_thr: std.Thread,

loop: Loop,

ticks: Ticks,
timers: std.AutoHashMap(u64, *Timer),
animations: std.AutoHashMap(u64, *BaseAnimation),
next_id: u64 = 1,

root: *Root,

needs_draw: bool = true,

size: vaxis.Winsize,

pub fn create(alloc: Allocator) !*App {
    var self = try alloc.create(App);

    var screen = try Screen.init(alloc, .{ .cols = 0, .rows = 0, .x_pixel = 0, .y_pixel = 0 });
    errdefer screen.deinit(alloc);

    var renderer = try Renderer.init(alloc, &self.tty, &self.screen);
    errdefer renderer.deinit();

    var renderer_thread = try RendererThread.init(alloc, &self.renderer);
    errdefer renderer_thread.deinit();

    var loop = try Loop.init(alloc, self);
    errdefer loop.deinit();

    var tty = try vaxis.Tty.init(&tty_buffer);
    self.tty = tty;
    errdefer tty.deinit();

    const events_thread = EventsThread.init(alloc, &self.tty, loop.mailbox, loop.wakeup);

    var ticks = Ticks.init(alloc, {});
    errdefer ticks.deinit();

    var timers = std.AutoHashMap(u64, *Timer).init(alloc);
    errdefer timers.deinit();

    var animations = std.AutoHashMap(u64, *BaseAnimation).init(alloc);
    errdefer animations.deinit();

    const root = try Root.create(alloc, "root");
    errdefer root.destroy(alloc);

    self.* = .{
        .alloc = alloc,
        .screen = screen,
        .renderer = renderer,
        .renderer_thread = renderer_thread,
        .renderer_thr = undefined,
        .tty = tty,
        .loop = loop,
        .events_thread = events_thread,
        .events_thr = undefined,
        .ticks = ticks,
        .timers = timers,
        .animations = animations,
        .root = root,
        .size = .{ .cols = 0, .rows = 0, .x_pixel = 0, .y_pixel = 0 },
    };

    self.events_thr = try std.Thread.spawn(.{}, EventsThread.threadMain, .{&self.events_thread});
    self.renderer_thr = try std.Thread.spawn(.{}, RendererThread.threadMain, .{&self.renderer_thread});

    return self;
}

pub fn destroy(self: *App) void {
    {
        self.renderer_thread.stop.notify() catch |err| {
            log.err("error notifying renderer thread to stop, may stall err={}", .{err});
        };
        self.renderer_thr.join();
    }

    {
        self.events_thread.stop();
        self.events_thr.join();
    }

    self.renderer_thread.deinit();
    self.loop.deinit();

    self.root.destroy(self.alloc);
    self.ticks.deinit();
    self.timers.deinit();
    self.animations.deinit();

    self.renderer.deinit();
}

pub fn run(self: *App) !void {
    const winsize = try vaxis.Tty.getWinsize(self.tty.fd);

    _ = self.loop.mailbox.push(.{ .resize = winsize }, .instant);
    try self.loop.wakeup.notify();

    self.loop.run();
}

pub fn draw(self: *App) !void {
    if (!self.needs_draw) return;
    self.needs_draw = false;

    var root = self.root.element;

    const ctx: Element.Context = .{
        .mailbox = self.loop.mailbox,
        .wakeup = self.loop.wakeup,
        .needs_draw = &self.needs_draw,
    };

    const screen = &self.screen;
    const buffer = screen.writeBuffer();

    if (buffer.width != self.size.cols or buffer.height != self.size.rows) {
        try screen.resizeWriteBuffer(self.alloc, self.size);
    }

    try root.update(ctx);
    root.draw(buffer);

    screen.swapWrite();

    try self.renderer_thread.wakeup.notify();
}

pub fn processTicks(self: *App) !void {
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

pub fn addTick(self: *App, tick: Tick) !void {
    const was_empty = self.ticks.count() == 0;
    const old_min = self.ticks.peek();

    try self.ticks.add(tick);

    if (was_empty or (old_min != null and tick.next < old_min.?.next)) {
        try self.loop.reschedule_tick.notify();
    }
}

pub fn registerTimer(self: *App, timer: *Timer) !void {
    timer.id = self.next_id;
    self.next_id += 1;
    try self.timers.put(timer.id, timer);
}

pub fn unregisterTimer(self: *App, id: u64) void {
    _ = self.timers.remove(id);
}

pub fn registerAnimation(self: *App, animation: *BaseAnimation) !void {
    animation.id = self.next_id;
    self.next_id += 1;
    try self.animations.put(animation.id, animation);
}

pub fn unregisterAnimation(self: *App, id: u64) void {
    _ = self.animations.remove(id);
}

pub fn startTimer(self: *App, timer: *Timer) !void {
    if (timer.id == 0) {
        try self.registerTimer(timer);
    }
    timer.state = .active;
    try self.addTick(timer.toTick());
}

pub fn pauseTimer(self: *App, id: u64) void {
    if (self.timers.get(id)) |timer| {
        if (timer.state == .active) {
            timer.state = .paused;
        }
    }
}

pub fn resumeTimer(self: *App, id: u64) !void {
    if (self.timers.get(id)) |timer| {
        if (timer.state == .paused) {
            timer.state = .active;
            try self.addTick(timer.toTick());
        }
    }
}

pub fn cancelTimer(self: *App, id: u64) void {
    if (self.timers.get(id)) |timer| {
        timer.state = .cancelled;
        self.unregisterTimer(id);
    }
}

pub fn startAnimation(self: *App, animation: *BaseAnimation) !void {
    if (animation.id == 0) {
        try self.registerAnimation(animation);
    }
    animation.anim_state = .active;
    animation.start_time = std.time.microTimestamp();
    animation.elapsed_at_pause = 0;
    try self.addTick(animation.toTick());
}

pub fn pauseAnimation(self: *App, id: u64) void {
    if (self.animations.get(id)) |animation| {
        if (animation.anim_state == .active) {
            animation.anim_state = .paused;
        }
    }
}

pub fn resumeAnimation(self: *App, id: u64) !void {
    if (self.animations.get(id)) |animation| {
        if (animation.anim_state == .paused) {
            const now = std.time.microTimestamp();
            animation.start_time = now - animation.elapsed_at_pause;
            animation.anim_state = .active;
            try self.addTick(animation.toTick());
        }
    }
}

pub fn cancelAnimation(self: *App, id: u64) void {
    if (self.animations.get(id)) |animation| {
        animation.anim_state = .cancelled;
        self.unregisterAnimation(id);
    }
}

pub fn resize(self: *App, size: vaxis.Winsize) !void {
    if (self.size.rows == size.rows and self.size.cols == size.cols) return;

    self.size = size;

    self.needs_draw = true;
}
