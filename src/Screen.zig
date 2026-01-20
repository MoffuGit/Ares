const std = @import("std");
const vaxis = @import("vaxis");
const Allocator = std.mem.Allocator;
const Buffer = @import("Buffer.zig");
const Cell = vaxis.Cell;

pub const Screen = @This();

const AtomicU8 = std.atomic.Value(u8);

const Method = vaxis.gwidth.Method;

buffers: [3]Buffer,
write_idx: u8 = 0,
ready_idx: AtomicU8 = .init(3),
read_idx: u8 = 2,

cursor_row: u16 = 0,
cursor_col: u16 = 0,
cursor_vis: bool = false,

width_pix: u16 = 0,
height_pix: u16 = 0,

width_method: Method = .wcwidth,

mouse_shape: vaxis.Mouse.Shape = .default,
cursor_shape: Cell.CursorShape = .default,

pub fn init(alloc: Allocator, size: vaxis.Winsize) !Screen {
    return .{
        .buffers = .{
            try Buffer.init(alloc, size.cols, size.rows),
            try Buffer.init(alloc, size.cols, size.rows),
            try Buffer.init(alloc, size.cols, size.rows),
        },
        .width_pix = size.x_pixel,
        .height_pix = size.y_pixel,
    };
}

pub fn deinit(self: *Screen, alloc: Allocator) void {
    for (&self.buffers) |*buffer| {
        buffer.deinit(alloc);
    }
}

pub fn swapWrite(self: *Screen) void {
    const old_ready = self.ready_idx.swap(self.write_idx, .acq_rel);
    if (old_ready < 3 and old_ready != self.read_idx) {
        self.write_idx = old_ready;
    } else {
        self.write_idx = self.findFreeBuffer();
    }
}

pub fn swapRead(self: *Screen) bool {
    const ready = self.ready_idx.load(.acquire);
    if (ready >= 3) return false;

    const old_read = self.read_idx;
    const swapped = self.ready_idx.cmpxchgStrong(ready, old_read, .acq_rel, .acquire);

    if (swapped == null) {
        self.read_idx = ready;
        return true;
    }
    return false;
}

pub fn writeBuffer(self: *Screen) *Buffer {
    return &self.buffers[self.write_idx];
}

pub fn readBuffer(self: *Screen) *Buffer {
    return &self.buffers[self.read_idx];
}

fn findFreeBuffer(self: *Screen) u8 {
    const ready = self.ready_idx.load(.acquire);
    for (0..3) |i| {
        const idx: u8 = @intCast(i);
        if (idx != self.read_idx and (ready >= 3 or idx != ready)) {
            return idx;
        }
    }
    return (self.write_idx + 1) % 3;
}

pub fn resizeWriteBuffer(self: *Screen, alloc: Allocator, size: vaxis.Winsize) !void {
    const buffer = &self.buffers[self.write_idx];
    buffer.deinit(alloc);
    buffer.* = try Buffer.init(alloc, size.cols, size.rows);
    self.width_pix = size.x_pixel;
    self.height_pix = size.y_pixel;
}

pub fn toVaxisScreen(self: *Screen) vaxis.Screen {
    const buffer = self.readBuffer();
    return .{
        .width = buffer.width,
        .height = buffer.height,
        .width_pix = self.width_pix,
        .height_pix = self.height_pix,
        .buf = buffer.buf,
        .cursor_row = self.cursor_row,
        .cursor_col = self.cursor_col,
        .cursor_vis = self.cursor_vis,
        .width_method = self.width_method,
        .mouse_shape = self.mouse_shape,
        .cursor_shape = self.cursor_shape,
    };
}
