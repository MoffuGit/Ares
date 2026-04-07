const Termio = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const ghostty_vt = @import("ghostty-vt");
const sizepkg = @import("size.zig");
const SharedState = @import("SharedState.zig");
const Renderer = @import("Renderer.zig");
const RendererThread = @import("renderer/Thread.zig");
const Grid = @import("font/mod.zig").Grid;

pub const Thread = @import("termio/Thread.zig").Thread;

const log = std.log.scoped(.termio);

pub const InitConfig = struct {};

alloc: Allocator,
grid: *Grid,
term: ghostty_vt.Terminal,

pub fn init(
    alloc: Allocator,
    grid: *Grid,
    _: *SharedState,
    _: *Renderer,
    _: *RendererThread,
    screen_size: sizepkg.ScreenSize,
    _: InitConfig,
) !Termio {
    const grid_size = (sizepkg.Size{
        .screen = screen_size,
        .cell = grid.cellSize(),
    }).grid();

    var term = try ghostty_vt.Terminal.init(alloc, .{
        .cols = grid_size.columns,
        .rows = grid_size.rows,
        .max_scrollback = 1000,
    });
    errdefer term.deinit(alloc);

    return .{
        .alloc = alloc,
        .grid = grid,
        .term = term,
    };
}

pub fn deinit(self: *Termio) void {
    self.term.deinit(self.alloc);
}

pub fn resize(self: *Termio, size: sizepkg.ScreenSize) void {
    const grid_size = (sizepkg.Size{
        .screen = size,
        .cell = self.grid.cellSize(),
    }).grid();

    self.term.resize(self.alloc, grid_size.columns, grid_size.rows) catch |err| {
        log.err("failed to resize terminal err={}", .{err});
    };
}
