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
    if (self.size.x_pixel == size.x_pixel and self.size.y_pixel == size.y_pixel) return;
    self.size = size;
    self.rebuild = true;
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
    if (self.size.cols == 0 or self.size.rows == 0) return;

    const needs_redraw = self.rebuild or sync;
    defer self.rebuild = false;

    if (!needs_redraw) return;

    try self.vx.resize(self.alloc, self.tty.writer(), self.size);

    const window = self.vx.window();

    window.clear();

    window.fill(.{ .style = .{ .bg = .{ .rgba = .{ 0, 0, 0, 255 } }, .fg = .{ .rgba = .{ 0, 0, 0, 255 } } } });

    try self.vx.render(self.tty.writer());
}
