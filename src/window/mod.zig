pub const Window = @This();

const std = @import("std");
const vaxis = @import("vaxis");
const xev = @import("../global.zig").xev;
const Allocator = std.mem.Allocator;

const RendererMailbox = @import("../renderer/Thread.zig").Mailbox;

alloc: Allocator,

screen: vaxis.Screen,
render: bool = false,
render_wakeup: xev.Async,
mutex: std.Thread.Mutex = .{},

pub fn init(alloc: Allocator, render_wakeup: xev.Async) !Window {
    var screen = try vaxis.Screen.init(
        alloc,
        .{
            .cols = 0,
            .rows = 0,
            .x_pixel = 0,
            .y_pixel = 0,
        },
    );
    errdefer screen.deinit();

    return .{ .alloc = alloc, .screen = screen, .render_wakeup = render_wakeup };
}

pub fn deinit(self: *Window) void {
    self.screen.deinit(self.alloc);
}

pub fn resize(self: *Window, size: vaxis.Winsize) !void {
    {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.screen.deinit(self.alloc);
        self.screen = try vaxis.Screen.init(self.alloc, size);

        const cell: vaxis.Cell = .{
            .style = .{ .bg = .{ .rgba = .{ 0, 0, 0, 255 } }, .fg = .{ .rgba = .{ 0, 0, 0, 255 } } },
        };
        @memset(self.screen.buf, cell);
        self.screen.cursor_vis = false;
        self.screen.cursor_shape = .default;

        self.render = true;
    }

    try self.render_wakeup.notify();
}
