const std = @import("std");
const vaxis = @import("vaxis");

const Allocator = std.mem.Allocator;
const Screen = @import("../Screen.zig");
const SharedContext = @import("../SharedContext.zig");

pub const Renderer = @This();

alloc: Allocator,

size: vaxis.Winsize,

shared_context: *SharedContext,
screen: *Screen,

pub fn init(alloc: Allocator, shared: *SharedContext, screen: *Screen) !Renderer {
    return .{
        .shared_context = shared,
        .alloc = alloc,
        .screen = screen,
        .size = .{ .cols = 0, .rows = 0, .x_pixel = 0, .y_pixel = 0 },
    };
}

pub fn deinit(self: *Renderer) void {
    _ = self;
    // TODO: migrate vx and tty fields from old_src
    // self.vx.deinit(self.alloc, self.tty.writer());
}

pub fn threadEnter(self: *Renderer) !void {
    const shared = self.shared_context;
    const vx = &shared.vx;
    const tty = &shared.tty;

    vx.caps.kitty_keyboard = true;
    vx.caps.sgr_pixels = true;

    try vx.enterAltScreen(tty.writer());
    try vx.queryTerminal(tty.writer(), 1 * std.time.ns_per_s);
    try vx.setBracketedPaste(tty.writer(), true);
    try vx.subscribeToColorSchemeUpdates(tty.writer());
    try vx.setMouseMode(tty.writer(), true);
}

pub fn resize(self: *Renderer, size: vaxis.Winsize) !void {
    const shared = self.shared_context;
    try shared.vx.resize(self.alloc, shared.tty.writer(), size);
    self.size = size;
}

pub fn threadExit(self: *Renderer) void {
    const writer = self.shared_context.tty.writer();
    writer.writeAll(vaxis.ctlseqs.color_scheme_reset) catch {};
    writer.writeAll(vaxis.ctlseqs.in_band_resize_reset) catch {};

    writer.flush() catch {};
}

pub fn renderFrame(self: *Renderer) !void {
    const screen = self.screen;
    const shared = self.shared_context;

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

        screen.width_method = shared.vx.caps.unicode;
    }

    var vaxis_screen = screen.toVaxisScreen(buffer);
    try shared.vx.render(&vaxis_screen, shared.tty.writer());
}
