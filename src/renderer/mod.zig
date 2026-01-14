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

pub fn drawFrame(self: *Renderer, sync: bool) !void {
    var needs_redraw: bool = undefined;
    {
        self.window.mutex.lock();
        defer self.window.mutex.unlock();

        if (self.window.screen.width == 0 or self.window.screen.height == 0) return;

        needs_redraw = sync or self.window.render;
    }

    if (!needs_redraw) return;

    {
        self.window.mutex.lock();
        defer self.window.mutex.unlock();

        self.window.render = false;

        self.window.screen.width_method = self.vx.caps.unicode;

        const buf = try self.alloc.alloc(vaxis.Cell, self.window.screen.buf.len);

        @memcpy(buf, self.window.screen.buf);

        self.vx.screen = self.window.screen;
        self.vx.screen.buf = buf;
    }

    if (self.vx.screen.height != self.vx.screen_last.height or self.vx.screen.width != self.vx.screen_last.width) {
        self.vx.screen_last.deinit(self.alloc);
        self.vx.screen_last = try vaxis.AllocatingScreen.init(self.alloc, self.vx.screen.width, self.vx.screen.height);

        // if (self.vx.state.alt_screen)
        //     try self.tty.writer().writeAll(vaxis.ctlseqs.home)
        // else {
        //     for (0..self.vx.state.cursor.row) |_| {
        //         try self.tty.writer().writeAll(vaxis.ctlseqs.ri);
        //     }
        //     try self.tty.writer().writeByte('\r');
        // }
        // self.vx.state.cursor.row = 0;
        // self.vx.state.cursor.col = 0;
        // try self.tty.writer().writeAll(vaxis.ctlseqs.sgr_reset ++ vaxis.ctlseqs.erase_below_cursor);
        // try self.tty.writer().flush();
    }

    try self.vx.render(self.tty.writer());
}
