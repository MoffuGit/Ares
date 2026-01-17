pub const Renderer = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const vaxis = @import("vaxis");
const SharedState = @import("../SharedState.zig");

alloc: Allocator,

size: vaxis.Winsize,
vx: vaxis.Vaxis,
render: bool,

tty: *vaxis.Tty,

shared_state: *SharedState,

pub fn init(alloc: Allocator, tty: *vaxis.Tty, shared_state: *SharedState) !Renderer {
    const vx = try vaxis.Vaxis.init(alloc, .{});

    return .{
        .vx = vx,
        .tty = tty,
        .alloc = alloc,
        .render = false,
        .shared_state = shared_state,
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

pub fn resize(self: *Renderer, size: vaxis.Winsize) !void {
    try self.vx.resize(self.alloc, self.tty.writer(), size);
    self.size = size;
    self.render = true;
}

pub fn threadExit(self: *Renderer) void {
    _ = self;
}

pub fn renderFrame(self: *Renderer, sync: bool) !void {
    const shared_state = self.shared_state;

    const has_new_frame = shared_state.swapRead();

    if (!has_new_frame and !sync and !self.render) return;
    defer self.render = false;

    const read_screen = shared_state.readBuffer();

    const size_change = self.size.cols != read_screen.width or self.size.rows != read_screen.height;

    if (size_change) {
        const size: vaxis.Winsize = .{
            .cols = read_screen.width,
            .rows = read_screen.height,
            .x_pixel = read_screen.width_pix,
            .y_pixel = read_screen.height_pix,
        };

        try self.resize(size);

        read_screen.width_method = self.vx.caps.unicode;
    }

    try self.vx.render(read_screen, self.tty.writer());
}
