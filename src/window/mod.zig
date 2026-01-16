pub const Window = @This();

const std = @import("std");
const vaxis = @import("vaxis");
const xev = @import("../global.zig").xev;
const Allocator = std.mem.Allocator;
const SharedState = @import("../SharedState.zig");
const Buffer = @import("../Buffer.zig");
const Element = @import("Element.zig");

const Root = @import("Root.zig");

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

alloc: Allocator,

render_wakeup: xev.Async,
render_mailbox: *RendererMailbox,

shared_state: *SharedState,
buffer: Buffer,

timers: Timers,

root: *Root,

size: vaxis.Winsize,

pub fn init(
    alloc: Allocator,
    render_wakeup: xev.Async,
    render_mailbox: *RendererMailbox,
    shared_state: *SharedState,
    window_mailbox: *WindowMailbox,
    window_wakeup: xev.Async,
) !Window {
    const root = try alloc.create(Root);
    errdefer alloc.destroy(root);

    root.* = Root.init(alloc);

    var buffer = try Buffer.init(alloc, 0, 0);
    errdefer buffer.deinit(alloc);

    var timers = Timers.init(alloc, {});
    errdefer timers.deinit();

    root.element.context = .{
        .mailbox = window_mailbox,
        .wakeup = window_wakeup,
    };

    try root.setup();

    return .{
        .root = root,
        .timers = timers,
        .alloc = alloc,
        .buffer = buffer,
        .render_wakeup = render_wakeup,
        .render_mailbox = render_mailbox,
        .shared_state = shared_state,
        .size = .{
            .cols = 0,
            .rows = 0,
            .x_pixel = 0,
            .y_pixel = 0,
        },
    };
}

pub fn deinit(self: *Window) void {
    self.buffer.deinit(self.alloc);
    self.alloc.destroy(self.root);
    self.timers.deinit();
}

pub fn draw(self: *Window) !void {
    try self.tick();

    try self.root.element.update();
    try self.root.element.draw(&self.buffer);

    {
        const shared_state = self.shared_state;
        shared_state.mutex.lock();
        defer shared_state.mutex.unlock();

        @memcpy(shared_state.screen.buf, self.buffer.buf);

        shared_state.render = true;
    }

    try self.render_wakeup.notify();
}

pub fn tick(self: *Window) !void {
    const now = std.time.microTimestamp();
    while (self.timers.peek()) |peek| {
        if (peek.next > now) break;
        const timer = self.timers.remove();
        if (timer.callback(timer.userdata, now)) |new| {
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
    try self.timers.add(timer);
}

pub fn resize(self: *Window, size: vaxis.Winsize) !void {
    if (self.size.rows == size.rows and self.size.cols == size.cols) return;

    self.size = size;

    self.buffer.deinit(self.alloc);
    self.buffer = try Buffer.init(self.alloc, self.size.cols, self.size.rows);

    {
        const shared_state = self.shared_state;

        shared_state.mutex.lock();
        defer shared_state.mutex.unlock();

        shared_state.screen.deinit(self.alloc);
        shared_state.screen = try .init(self.alloc, self.size);
    }

    _ = self.render_mailbox.push(.{ .resize = size }, .instant);
    try self.render_wakeup.notify();
}
