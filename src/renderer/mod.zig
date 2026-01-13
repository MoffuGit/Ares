pub const Renderer = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const vaxis = @import("vaxis");

alloc: Allocator,

size: vaxis.Winsize,
vx: vaxis.Vaxis,
tty: *vaxis.Tty,

rebuild: bool = false,

pub fn init(alloc: Allocator, tty: *vaxis.Tty) !Renderer {
    const vx = try vaxis.Vaxis.init(alloc, .{});

    return .{ .vx = vx, .tty = tty, .alloc = alloc, .size = .{ .cols = 0, .rows = 0, .x_pixel = 0, .y_pixel = 0 } };
}

pub fn deinit(self: *Renderer) void {
    self.vx.deinit(self.alloc, self.tty.writer());
}

pub fn resize(self: *Renderer, size: vaxis.Winsize) !void {
    self.size = size;

    self.vx.screen.deinit(self.alloc);
    self.vx.screen = try vaxis.Screen.init(self.alloc, size);
    self.vx.screen.width_method = self.vx.caps.unicode;
    self.vx.screen_last.deinit(self.alloc);
    self.vx.screen_last = try vaxis.AllocatingScreen.init(self.alloc, size.cols, size.rows);
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

pub fn drawFrame(self: *Renderer, sync: bool) !void {
    const size = try vaxis.Tty.getWinsize(self.tty.fd);

    if (size.cols == 0 or size.rows == 0) return;

    const size_changed = self.size.cols != size.cols or self.size.rows != size.rows;

    const needs_redraw = self.rebuild or sync or size_changed;

    if (!needs_redraw) try self.vx.render(self.tty.writer());

    self.rebuild = false;

    if (size_changed) {
        try self.resize(size);
    }

    const window = self.vx.window();
    window.fill(.{ .style = .{ .bg = .{ .rgba = .{ 0, 0, 0, 255 } }, .fg = .{ .rgba = .{ 0, 0, 0, 255 } } } });
    window.hideCursor();
    window.setCursorShape(.default);

    try self.vx.render(self.tty.writer());
}
