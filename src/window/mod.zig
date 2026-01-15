pub const Window = @This();

const std = @import("std");
const vaxis = @import("vaxis");
const xev = @import("../global.zig").xev;
const Allocator = std.mem.Allocator;

const Root = @import("Root.zig");

const RendererMailbox = @import("../renderer/Thread.zig").Mailbox;

alloc: Allocator,

render_wakeup: xev.Async,

size: vaxis.Winsize,
buffer: []vaxis.Cell = &.{},

render: bool = false,

mutex: std.Thread.Mutex = .{},

root: *Root,

pub fn init(
    alloc: Allocator,
    render_wakeup: xev.Async,
    root: *Root,
) !Window {
    const buffer = try alloc.alloc(vaxis.Cell, 0);
    errdefer alloc.free(buffer);

    return .{
        .root = root,
        .alloc = alloc,
        .render_wakeup = render_wakeup,
        .buffer = buffer,
        .size = .{ .cols = 0, .rows = 0, .x_pixel = 0, .y_pixel = 0 },
    };
}

pub fn deinit(self: *Window) void {
    self.alloc.free(self.buffer);
}

pub fn draw(self: *Window) !void {
    {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.root.element.update();

        try self.root.element.draw(self.buffer);

        self.render = true;
    }

    try self.render_wakeup.notify();
}

pub fn resize(self: *Window, size: vaxis.Winsize) !void {
    if (self.size.rows == size.rows and self.size.cols == size.cols) return;
    {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.alloc.free(self.buffer);
        self.buffer = try self.alloc.alloc(vaxis.Cell, @as(usize, @intCast(size.cols)) * size.rows);

        const cell: vaxis.Cell = .{
            .style = .{ .bg = .{ .rgba = .{ 0, 0, 0, 255 } }, .fg = .{ .rgba = .{ 0, 0, 0, 255 } } },
        };
        @memset(self.buffer, cell);

        self.size = size;
    }

    try self.render_wakeup.notify();
}
