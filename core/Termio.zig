const Termio = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const ghostty_vt = @import("ghostty-vt");
const sizepkg = @import("size.zig");
const inputpkg = @import("input.zig");
const Renderer = @import("Renderer.zig");
const RendererThread = @import("renderer/Thread.zig");
const Grid = @import("font/mod.zig").Grid;
const Terminal = @import("Terminal.zig");

pub const Thread = @import("termio/Thread.zig").Thread;

const log = std.log.scoped(.termio);

alloc: Allocator,
grid: *Grid,
renderer_thread: *RendererThread,
state: *Terminal,

pub fn init(
    alloc: Allocator,
    grid: *Grid,
    _: *Renderer,
    renderer_thread: *RendererThread,
    _: sizepkg.ScreenSize,
    state: *Terminal,
) !Termio {
    return .{
        .alloc = alloc,
        .grid = grid,
        .renderer_thread = renderer_thread,
        .state = state,
    };
}

pub fn deinit(self: *Termio) void {
    _ = self;
}

pub fn resize(self: *Termio, size: sizepkg.ScreenSize) void {
    const grid_size = (sizepkg.Size{
        .screen = size,
        .cell = self.grid.cellSize(),
    }).grid();

    self.state.term.resize(self.alloc, grid_size.columns, grid_size.rows) catch |err| {
        log.err("failed to resize terminal err={}", .{err});
    };
    self.state.rebuild_cells = true;
}

pub fn mouseButton(_: *Termio, event: inputpkg.MouseButtonEvent) void {
    log.debug("mouse button={s} action={s} x={d:.1} y={d:.1} mods=0x{x}", .{
        @tagName(event.button),
        @tagName(event.action),
        event.x,
        event.y,
        @as(u8, @bitCast(event.mods)),
    });
}

pub fn mouseMove(_: *Termio, event: inputpkg.MouseMoveEvent) void {
    log.debug("mouse move x={d:.1} y={d:.1} mods=0x{x}", .{
        event.x,
        event.y,
        @as(u8, @bitCast(event.mods)),
    });
}
