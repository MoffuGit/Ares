const Editor = @This();

const std = @import("std");
const sizepkg = @import("../size.zig");
const RendererThread = @import("../renderer/Thread.zig");

size: sizepkg.Size,

rows: u16,
cols: u16,

mutex: std.Thread.Mutex,

renderer_thread: *RendererThread,

pub fn init(size: sizepkg.Size, mutex: std.Thread.Mutex, thread: *RendererThread) Editor {
    const grid_size = size.grid();
    return .{ .size = size, .cols = grid_size.columns, .rows = grid_size.rows, .mutex = mutex, .renderer_thread = thread };
}

pub fn deinit(self: *Editor) void {
    _ = self;
}

pub fn resize(self: *Editor, size: sizepkg.Size) void {
    self.size = size;
    const grid_size = self.size.grid();

    self.mutex.lock();
    defer self.mutex.unlock();

    self.rows = grid_size.rows;
    self.cols = grid_size.columns;

    self.renderer_thread.wakeup.notify() catch {};
}
