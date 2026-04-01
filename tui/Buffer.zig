const std = @import("std");
const vaxis = @import("vaxis");
const assert = std.debug.assert;

const Cell = vaxis.Cell;
const Winsize = vaxis.Winsize;
const Allocator = std.mem.Allocator;
const ClipRect = @import("ClipRect.zig");

pub const Buffer = @This();

const max_clip_depth = 8;

alloc: Allocator,
buf: []Cell = &.{},

width: u16 = 0,
height: u16 = 0,

clip_stack: std.ArrayList(ClipRect) = .{},
current_clip: ?ClipRect = null,

opacity_stack: std.ArrayList(f32) = .{},
current_opacity: f32 = 1.0,

offset_stack: std.ArrayList(struct { dx: i32, dy: i32 }) = .{},
current_offset_x: i32 = 0,
current_offset_y: i32 = 0,

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
    self.opacity_stack.deinit(self.alloc);
    self.offset_stack.deinit(self.alloc);
    self.alloc.free(self.buf);
}

pub fn pushOpacity(self: *Buffer, opacity: f32) void {
    self.opacity_stack.append(self.alloc, opacity) catch {};
    self.current_opacity = @min(self.current_opacity, opacity);
}

pub fn popOpacity(self: *Buffer) void {
    _ = self.opacity_stack.pop();
    self.recalculateOpacity();
}

fn recalculateOpacity(self: *Buffer) void {
    self.current_opacity = 1.0;
    for (self.opacity_stack.items) |opacity| {
        self.current_opacity = @min(self.current_opacity, opacity);
    }
}

pub fn pushClip(self: *Buffer, x: u16, y: u16, w: u16, h: u16) void {
    const new_clip = translateRect(x, y, w, h, self.current_offset_x, self.current_offset_y);

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
    if (self.clip_stack.items.len > 0 and self.current_clip == null) {
        return true;
    }

    if (self.current_clip) |clip| {
        return !clip.contains(col, row);
    }
    return false;
}

pub fn setCell(self: *Buffer, col: u16, row: u16, cell: Cell) void {
    const translated = self.translatePoint(col, row) orelse return;
    if (translated.col >= self.width or translated.row >= self.height) return;
    if (self.isClipped(translated.col, translated.row)) return;

    const i = (@as(usize, @intCast(translated.row)) * self.width) + translated.col;
    assert(i < self.buf.len);
    self.buf[i] = if (self.current_opacity < 1.0) self.applyOpacity(cell) else cell;
}

fn applyOpacity(self: *const Buffer, cell: Cell) Cell {
    var c = cell;
    const o = self.current_opacity;
    if (c.style.fg.alpha() > 0) {
        c.style.fg = c.style.fg.setAlpha(o);
    }
    if (c.style.bg.alpha() > 0) {
        c.style.bg = c.style.bg.setAlpha(o);
    }
    if (c.style.ul.alpha() > 0) {
        c.style.ul = c.style.ul.setAlpha(o);
    }
    return c;
}

pub fn writeCell(self: *Buffer, col: u16, row: u16, cell: Cell) void {
    const translated = self.translatePoint(col, row) orelse return;

    if (self.readCell(translated.col, translated.row)) |other| {
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

pub fn pushOffset(self: *Buffer, dx: i32, dy: i32) void {
    self.offset_stack.append(self.alloc, .{ .dx = dx, .dy = dy }) catch {};
    self.current_offset_x += dx;
    self.current_offset_y += dy;
}

pub fn popOffset(self: *Buffer) void {
    if (self.offset_stack.items.len == 0) return;
    const offset = self.offset_stack.pop().?;
    self.current_offset_x -= offset.dx;
    self.current_offset_y -= offset.dy;
}

fn translatePoint(self: *const Buffer, col: u16, row: u16) ?struct { col: u16, row: u16 } {
    const translated_col = @as(i32, col) + self.current_offset_x;
    const translated_row = @as(i32, row) + self.current_offset_y;

    if (translated_col < 0 or translated_row < 0) return null;
    if (translated_col > std.math.maxInt(u16) or translated_row > std.math.maxInt(u16)) return null;

    return .{
        .col = @intCast(translated_col),
        .row = @intCast(translated_row),
    };
}

fn translateRect(x: u16, y: u16, width: u16, height: u16, dx: i32, dy: i32) ClipRect {
    const max_coord: i32 = std.math.maxInt(u16);
    const left = @as(i32, x) + dx;
    const top = @as(i32, y) + dy;
    const right = left + @as(i32, width);
    const bottom = top + @as(i32, height);

    const clamped_left = std.math.clamp(left, 0, max_coord);
    const clamped_top = std.math.clamp(top, 0, max_coord);
    const clamped_right = std.math.clamp(right, 0, max_coord);
    const clamped_bottom = std.math.clamp(bottom, 0, max_coord);

    if (clamped_left >= clamped_right or clamped_top >= clamped_bottom) {
        return .{ .x = 0, .y = 0, .width = 0, .height = 0 };
    }

    return .{
        .x = @intCast(clamped_left),
        .y = @intCast(clamped_top),
        .width = @intCast(clamped_right - clamped_left),
        .height = @intCast(clamped_bottom - clamped_top),
    };
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

test "offset stack translates writes and clips" {
    var buffer = try Buffer.init(testing.allocator, 5, 5);
    defer buffer.deinit();

    buffer.pushOffset(0, -2);
    defer buffer.popOffset();

    buffer.pushClip(0, 2, 1, 1);
    defer buffer.popClip();

    buffer.setCell(0, 2, .{ .char = .{ .grapheme = "X", .width = 1 } });
    buffer.setCell(0, 3, .{ .char = .{ .grapheme = "Y", .width = 1 } });

    try testing.expectEqualStrings("X", buffer.readCell(0, 0).?.char.grapheme);
    try testing.expectEqualStrings("", buffer.readCell(0, 1).?.char.grapheme);
}
