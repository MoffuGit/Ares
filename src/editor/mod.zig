const Editor = @This();

const std = @import("std");
const sizepkg = @import("../size.zig");
const RendererThread = @import("../renderer/Thread.zig");

//NOTE:
//Store data from a file that you select using swift
const msg = "Hello world!";

size: sizepkg.Size,

rows: u16,
cols: u16,

mutex: std.Thread.Mutex,

renderer_thread: *RendererThread,
cells: [msg.len]u32,

pub fn init(size: sizepkg.Size, mutex: std.Thread.Mutex, thread: *RendererThread) !Editor {
    const grid_size = size.grid();
    var cells_array: [msg.len]u32 = undefined;
    var i: usize = 0;

    var utf8 = (try std.unicode.Utf8View.init(msg)).iterator();
    while (utf8.nextCodepoint()) |codepoint| : (i += 1) {
        cells_array[i] = @intCast(codepoint);
    }
    return .{ .size = size, .cols = grid_size.columns, .rows = grid_size.rows, .mutex = mutex, .renderer_thread = thread, .cells = cells_array };
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
