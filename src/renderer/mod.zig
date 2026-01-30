pub const Renderer = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const vaxis = @import("vaxis");
const Screen = @import("../Screen.zig");

alloc: Allocator,

size: vaxis.Winsize,
vx: vaxis.Vaxis,

tty: *vaxis.Tty,

screen: *Screen,

pub fn init(alloc: Allocator, tty: *vaxis.Tty, screen: *Screen) !Renderer {
    const vx = try vaxis.init(alloc, .{});

    return .{
        .vx = vx,
        .tty = tty,
        .alloc = alloc,
        .screen = screen,
        .size = .{ .cols = 0, .rows = 0, .x_pixel = 0, .y_pixel = 0 },
    };
}

pub fn deinit(self: *Renderer) void {
    self.vx.deinit(self.alloc, self.tty.writer());
}

pub fn threadEnter(self: *Renderer) !void {
    const vx = &self.vx;
    const tty = self.tty;

    vx.caps.kitty_keyboard = true;

    try vx.enterAltScreen(tty.writer());
    try vx.queryTerminal(tty.writer(), 1 * std.time.ns_per_s);
    try vx.setBracketedPaste(tty.writer(), true);
    try vx.subscribeToColorSchemeUpdates(tty.writer());
    try vx.setMouseMode(tty.writer(), true);
    try vx.subscribeToColorSchemeUpdates(tty.writer());
}

pub fn resize(self: *Renderer, size: vaxis.Winsize) !void {
    try self.vx.resize(self.alloc, self.tty.writer(), size);
    self.size = size;
}

pub fn threadExit(self: *Renderer) void {
    const writer = self.tty.writer();
    writer.writeAll(vaxis.ctlseqs.color_scheme_reset) catch {};
    writer.writeAll(vaxis.ctlseqs.in_band_resize_reset) catch {};

    writer.flush() catch {};
}

pub fn renderFrame(self: *Renderer) !void {
    const screen = self.screen;

    const buffer = screen.currentBuffer() orelse return;

    defer screen.releaseBuffer();

    const size_change = self.size.cols != buffer.width or self.size.rows != buffer.height;

    if (size_change) {
        const size: vaxis.Winsize = .{
            .cols = buffer.width,
            .rows = buffer.height,
            .x_pixel = screen.width_pix,
            .y_pixel = screen.height_pix,
        };

        try self.resize(size);

        screen.width_method = self.vx.caps.unicode;
    }

    var vaxis_screen = screen.toVaxisScreen(buffer);
    try self.vx.render(&vaxis_screen, self.tty.writer());
}
