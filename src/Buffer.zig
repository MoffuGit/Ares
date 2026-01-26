const std = @import("std");
const assert = std.debug.assert;
const vaxis = @import("vaxis");
const Cell = vaxis.Cell;
const Winsize = vaxis.Winsize;
const Allocator = std.mem.Allocator;

pub const Buffer = @This();

buf: []Cell = &.{},

width: u16 = 0,
height: u16 = 0,

pub fn init(alloc: std.mem.Allocator, width: u16, height: u16) !Buffer {
    return .{
        .buf = try alloc.alloc(Cell, @as(usize, @intCast(width)) * height),
        .height = height,
        .width = width,
    };
}

pub fn deinit(self: *Buffer, alloc: Allocator) void {
    alloc.free(self.buf);
}

pub fn setCell(self: *Buffer, col: u16, row: u16, cell: Cell) void {
    if (col >= self.width or
        row >= self.height)
        return;
    const i = (@as(usize, @intCast(row)) * self.width) + col;
    assert(i < self.buf.len);
    self.buf[i] = cell;
}

pub fn writeCell(self: *Buffer, col: u16, row: u16, cell: Cell) void {
    if (self.readCell(col, row)) |other| {
        self.setCell(col, row, cell.blend(other));
    } else {
        self.setCell(col, row, cell);
    }
}

pub fn readCell(self: *const Buffer, col: u16, row: u16) ?Cell {
    if (col >= self.width or
        row >= self.height)
        return null;
    const i = (@as(usize, @intCast(row)) * self.width) + col;
    assert(i < self.buf.len);
    return self.buf[i];
}

pub fn clear(self: *Buffer) void {
    @memset(self.buf, .{});
}

pub fn fill(self: *Buffer, cell: Cell) void {
    @memset(self.buf, cell);
}

pub fn fillRect(self: *Buffer, x: u16, y: u16, width: u16, height: u16, cell: Cell) void {
    var row: u16 = 0;
    while (row < height) : (row += 1) {
        var col: u16 = 0;
        while (col < width) : (col += 1) {
            self.writeCell(x + col, y + row, cell);
        }
    }
}

fn coordsToIndex(self: *Buffer, x: u32, y: u32) u32 {
    return y * self.width + x;
}

fn indexToCoords(self: *Buffer, index: u32) struct { x: u32, y: u32 } {
    return .{
        .x = index % self.width,
        .y = index / self.width,
    };
}
