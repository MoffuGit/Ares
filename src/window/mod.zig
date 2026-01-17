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

pub const TimerCallback = *const fn (userdata: ?*anyopaque, time: i64) ?Timer;

pub const Timer = struct {
    next: i64,
    callback: TimerCallback,
    userdata: ?*anyopaque = null,

    pub fn lessThan(_: void, a: Timer, b: Timer) std.math.Order {
        return std.math.order(a.next, b.next);
    }
};

const Timers = std.PriorityQueue(Timer, void, Timer.lessThan);

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

timers: Timers,

root: *Element,

window_mailbox: *WindowMailbox,
window_wakeup: xev.Async,
reschedule_tick: xev.Async,

needs_draw: bool = true,

size: vaxis.Winsize,

pub fn init(alloc: Allocator, opts: Opts) !Window {
    var buffer = try Buffer.init(alloc, 0, 0);
    errdefer buffer.deinit(alloc);

    var timers = Timers.init(alloc, {});
    errdefer timers.deinit();

    return .{
        .root = opts.root,
        .timers = timers,
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

pub fn setup(self: *Window) !void {
    self.root.context = .{
        .mailbox = self.window_mailbox,
        .wakeup = self.window_wakeup,
        .needs_draw = &self.needs_draw,
    };
}

pub fn deinit(self: *Window) void {
    self.buffer.deinit(self.alloc);
    self.timers.deinit();
}

pub fn draw(self: *Window) !void {
    if (!self.needs_draw) return;
    self.needs_draw = false;

    var root = self.root;

    try root.update();
    try root.draw(&self.buffer);

    const shared_state = self.shared_state;
    const write_screen = shared_state.writeBuffer();

    if (write_screen.width != self.buffer.width or write_screen.height != self.buffer.height) {
        try shared_state.resizeWriteBuffer(self.alloc, self.size);
    }

    @memcpy(write_screen.buf, self.buffer.buf);
    shared_state.swapWrite();

    try self.render_wakeup.notify();
}

pub fn tick(self: *Window) !void {
    const now = std.time.microTimestamp();
    while (self.timers.peek()) |peek| {
        if (peek.next > now) break;
        const timer = self.timers.remove();
        if (timer.callback(timer.userdata, timer.next)) |new| {
            const clamped_next = if (new.next <= now) now + 1 else new.next;
            try self.timers.add(.{
                .next = clamped_next,
                .callback = new.callback,
                .userdata = new.userdata,
            });
        }
    }
}

pub fn addTimer(self: *Window, timer: Timer) !void {
    const was_empty = self.timers.count() == 0;
    const old_min = self.timers.peek();

    try self.timers.add(timer);

    if (was_empty or (old_min != null and timer.next < old_min.?.next)) {
        try self.reschedule_tick.notify();
    }
}

pub fn resize(self: *Window, size: vaxis.Winsize) !void {
    if (self.size.rows == size.rows and self.size.cols == size.cols) return;

    self.size = size;

    self.buffer.deinit(self.alloc);
    self.buffer = try Buffer.init(self.alloc, self.size.cols, self.size.rows);

    self.needs_draw = true;
}
