const Editor = @This();

const std = @import("std");
const sizepkg = @import("../size.zig");

size: sizepkg.Size,

rows: u16,
cols: u16,

mutex: std.Thread.Mutex = .{},

pub fn init(size: sizepkg.Size) Editor {
    const grid_size = size.grid();
    return .{
        .size = size,
        .cols = grid_size.columns,
        .rows = grid_size.rows,
    };
}

pub fn deinit(self: *Editor) void {
    _ = self;
}
