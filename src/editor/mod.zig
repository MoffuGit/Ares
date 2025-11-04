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

pub fn resize(self: *Editor, size: sizepkg.Size) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    self.size = size;
    const grid_size = self.size.grid();

    self.rows = grid_size.rows;
    self.cols = grid_size.columns;
}
