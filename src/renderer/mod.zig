pub const Renderer = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const vaxis = @import("vaxis");
const Window = @import("../window/mod.zig");

alloc: Allocator,

size: vaxis.Winsize,
vx: vaxis.Vaxis,
tty: *vaxis.Tty,

window: *Window,

pub fn init(alloc: Allocator, tty: *vaxis.Tty, window: *Window) !Renderer {
    const vx = try vaxis.Vaxis.init(alloc, .{});

    return .{
        .vx = vx,
        .tty = tty,
        .window = window,
        .alloc = alloc,
        .size = .{ .cols = 0, .rows = 0, .x_pixel = 0, .y_pixel = 0 },
    };
}

pub fn deinit(self: *Renderer) void {
    self.vx.deinit(self.alloc, self.tty.writer());
}

pub fn threadEnter(self: *Renderer) !void {
    const vx = &self.vx;
    const tty = self.tty;

    try vx.enterAltScreen(tty.writer());
    try vx.queryTerminal(tty.writer(), 1 * std.time.ns_per_s);
    try vx.setBracketedPaste(tty.writer(), true);
    try vx.subscribeToColorSchemeUpdates(tty.writer());
    try vx.setMouseMode(tty.writer(), true);
}

pub fn threadExit(self: *Renderer) void {
    _ = self;
}

pub fn renderFrame(self: *Renderer, sync: bool) !void {
    var needs_redraw: bool = undefined;
    var size_change: bool = undefined;
    {
        self.window.mutex.lock();
        defer self.window.mutex.unlock();

        if (self.window.size.rows == 0 or self.window.size.cols == 0) return;
        size_change = self.size.cols != self.window.size.cols or self.size.rows != self.window.size.rows;

        needs_redraw = sync or self.window.render or size_change;
    }

    if (!needs_redraw) return;

    {
        self.window.mutex.lock();
        defer self.window.mutex.unlock();

        self.window.render = false;

        if (size_change) {
            self.size = self.window.size;
            self.vx.screen.deinit(self.alloc);
            self.vx.screen = try vaxis.Screen.init(self.alloc, self.size);
            self.vx.screen.width_method = self.vx.caps.unicode;
            self.vx.screen_last.deinit(self.alloc);
            self.vx.screen_last = try vaxis.AllocatingScreen.init(self.alloc, self.size.cols, self.size.rows);
            self.vx.state.cursor.row = 0;
            self.vx.state.cursor.col = 0;
        }

        @memcpy(self.vx.screen.buf, self.window.buffer);
    }

    try self.vx.render(self.tty.writer());
}
