pub const Window = @This();

const std = @import("std");
const vaxis = @import("vaxis");
const xev = @import("../global.zig").xev;
const Allocator = std.mem.Allocator;
const SharedState = @import("../SharedState.zig");

const Root = @import("Root.zig");

const RendererMailbox = @import("../renderer/Thread.zig").Mailbox;

alloc: Allocator,

render_wakeup: xev.Async,
render_mailbox: *RendererMailbox,
shared_state: *SharedState,

size: vaxis.Winsize,

pub fn init(
    alloc: Allocator,
    render_wakeup: xev.Async,
    render_mailbox: *RendererMailbox,
    shared_state: *SharedState,
) !Window {
    return .{ .alloc = alloc, .render_wakeup = render_wakeup, .render_mailbox = render_mailbox, .shared_state = shared_state, .size = .{
        .cols = 0,
        .rows = 0,
        .x_pixel = 0,
        .y_pixel = 0,
    } };
}

pub fn deinit(self: *Window) void {
    _ = self;
}

pub fn draw(self: *Window) !void {
    {
        const shared_state = self.shared_state;
        shared_state.mutex.lock();
        defer shared_state.mutex.unlock();

        const win = shared_state.screen.window();
        win.fill(.{ .style = .{ .bg = .{ .rgba = .{ 255, 0, 0, 255 } } } });
    }

    try self.render_wakeup.notify();
}

pub fn resize(self: *Window, size: vaxis.Winsize) !void {
    if (self.size.rows == size.rows and self.size.cols == size.cols) return;

    self.size = size;

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
