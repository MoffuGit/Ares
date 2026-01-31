const std = @import("std");
const assert = std.debug.assert;
const vaxis = @import("vaxis");
const Cell = vaxis.Cell;
const Winsize = vaxis.Winsize;
const Allocator = std.mem.Allocator;
const ClipRect = @import("ClipRect.zig");
pub const Element = @import("element/mod.zig");

pub const Buffer = @This();

const max_clip_depth = 8;

alloc: Allocator,
buf: []Cell = &.{},

width: u16 = 0,
height: u16 = 0,

clip_stack: std.ArrayList(ClipRect) = .{},
current_clip: ?ClipRect = null,

pub fn init(alloc: std.mem.Allocator, width: u16, height: u16) !Buffer {
    return .{
        .alloc = alloc,
        .buf = try alloc.alloc(Cell, @as(usize, @intCast(width)) * height),
        .height = height,
        .width = width,
    };
}

pub fn deinit(self: *Buffer) void {
    self.clip_stack.deinit(self.alloc);
    self.alloc.free(self.buf);
}

pub fn pushClip(self: *Buffer, x: u16, y: u16, w: u16, h: u16) void {
    const new_clip = ClipRect{ .x = x, .y = y, .width = w, .height = h };

    const effective_clip = if (self.current_clip) |current|
        current.intersect(new_clip)
    else
        new_clip;

    self.clip_stack.append(self.alloc, new_clip) catch {};
    self.current_clip = effective_clip;
}

pub fn popClip(self: *Buffer) void {
    _ = self.clip_stack.pop();
    self.recalculateClip();
}

fn recalculateClip(self: *Buffer) void {
    if (self.clip_stack.items.len == 0) {
        self.current_clip = null;
        return;
    }

    var result: ?ClipRect = null;
    for (self.clip_stack.items) |clip| {
        if (result) |r| {
            result = r.intersect(clip);
        } else {
            result = clip;
        }
    }
    self.current_clip = result;
}

fn isClipped(self: *const Buffer, col: u16, row: u16) bool {
    if (self.current_clip) |clip| {
        return !clip.contains(col, row);
    }
    return false;
}

pub fn setCell(self: *Buffer, col: u16, row: u16, cell: Cell) void {
    if (col >= self.width or row >= self.height) return;
    if (self.isClipped(col, row)) return;

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

const testing = std.testing;

test "clip stack: no clip allows all writes" {
    var buffer = try Buffer.init(testing.allocator, 10, 10);
    defer buffer.deinit();

    buffer.setCell(5, 5, .{ .char = .{ .grapheme = "X", .width = 1 } });
    const cell = buffer.readCell(5, 5);
    try testing.expect(cell != null);
    try testing.expectEqualStrings("X", cell.?.char.grapheme);
}

test "clip stack: single clip blocks outside writes" {
    var buffer = try Buffer.init(testing.allocator, 10, 10);
    defer buffer.deinit();

    buffer.setCell(0, 0, .{ .char = .{ .grapheme = "A", .width = 1 } });

    buffer.pushClip(2, 2, 4, 4);

    buffer.setCell(0, 0, .{ .char = .{ .grapheme = "X", .width = 1 } });
    try testing.expectEqualStrings("A", buffer.readCell(0, 0).?.char.grapheme);

    buffer.setCell(3, 3, .{ .char = .{ .grapheme = "Y", .width = 1 } });
    try testing.expectEqualStrings("Y", buffer.readCell(3, 3).?.char.grapheme);
}

test "clip stack: nested clips intersect" {
    var buffer = try Buffer.init(testing.allocator, 20, 20);
    defer buffer.deinit();

    buffer.setCell(3, 3, .{ .char = .{ .grapheme = "O", .width = 1 } });
    buffer.setCell(12, 12, .{ .char = .{ .grapheme = "P", .width = 1 } });

    buffer.pushClip(0, 0, 10, 10);
    buffer.pushClip(5, 5, 10, 10);

    buffer.setCell(3, 3, .{ .char = .{ .grapheme = "A", .width = 1 } });
    try testing.expectEqualStrings("O", buffer.readCell(3, 3).?.char.grapheme);

    buffer.setCell(12, 12, .{ .char = .{ .grapheme = "B", .width = 1 } });
    try testing.expectEqualStrings("P", buffer.readCell(12, 12).?.char.grapheme);

    buffer.setCell(7, 7, .{ .char = .{ .grapheme = "C", .width = 1 } });
    try testing.expectEqualStrings("C", buffer.readCell(7, 7).?.char.grapheme);
}

test "clip stack: pop restores previous clip" {
    var buffer = try Buffer.init(testing.allocator, 20, 20);
    defer buffer.deinit();

    buffer.setCell(3, 3, .{ .char = .{ .grapheme = "O", .width = 1 } });

    buffer.pushClip(0, 0, 10, 10);
    buffer.pushClip(5, 5, 10, 10);

    buffer.setCell(3, 3, .{ .char = .{ .grapheme = "X", .width = 1 } });
    try testing.expectEqualStrings("O", buffer.readCell(3, 3).?.char.grapheme);

    buffer.popClip();

    buffer.setCell(3, 3, .{ .char = .{ .grapheme = "Y", .width = 1 } });
    try testing.expectEqualStrings("Y", buffer.readCell(3, 3).?.char.grapheme);
}

test "clip stack: pop all restores no clipping" {
    var buffer = try Buffer.init(testing.allocator, 10, 10);
    defer buffer.deinit();

    buffer.setCell(0, 0, .{ .char = .{ .grapheme = "O", .width = 1 } });

    buffer.pushClip(5, 5, 2, 2);

    buffer.setCell(0, 0, .{ .char = .{ .grapheme = "X", .width = 1 } });
    try testing.expectEqualStrings("O", buffer.readCell(0, 0).?.char.grapheme);

    buffer.popClip();

    buffer.setCell(0, 0, .{ .char = .{ .grapheme = "Y", .width = 1 } });
    try testing.expectEqualStrings("Y", buffer.readCell(0, 0).?.char.grapheme);
}
