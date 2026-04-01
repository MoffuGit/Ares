const std = @import("std");
const Allocator = std.mem.Allocator;
const ClipRect = @import("../ClipRect.zig");

pub const HitGrid = @This();

pub const no_hit: u64 = std.math.maxInt(u64);

const max_clip_depth = 8;

alloc: Allocator,

grid: []u64 = &.{},
width: u16 = 0,
height: u16 = 0,

clip_stack: std.ArrayList(ClipRect) = .{},
current_clip: ?ClipRect = null,

offset_stack: std.ArrayList(struct { dx: i32, dy: i32 }) = .{},
current_offset_x: i32 = 0,
current_offset_y: i32 = 0,

pub fn init(alloc: Allocator, width: u16, height: u16) !HitGrid {
    const size = @as(usize, width) * height;
    const grid = try alloc.alloc(u64, size);
    @memset(grid, no_hit);
    return .{
        .alloc = alloc,
        .grid = grid,
        .width = width,
        .height = height,
    };
}

pub fn deinit(
    self: *HitGrid,
) void {
    self.clip_stack.deinit(self.alloc);
    self.offset_stack.deinit(self.alloc);
    if (self.grid.len > 0) {
        self.alloc.free(self.grid);
    }
}

pub fn resize(self: *HitGrid, width: u16, height: u16) !void {
    self.deinit();
    self.* = try HitGrid.init(self.alloc, width, height);
}

pub fn clear(self: *HitGrid) void {
    @memset(self.grid, no_hit);
}

pub fn pushClip(self: *HitGrid, x: u16, y: u16, w: u16, h: u16) void {
    const new_clip = translateRect(x, y, w, h, self.current_offset_x, self.current_offset_y);

    const effective_clip = if (self.current_clip) |current|
        current.intersect(new_clip)
    else
        new_clip;

    self.clip_stack.append(self.alloc, new_clip) catch {};
    self.current_clip = effective_clip;
}

pub fn popClip(self: *HitGrid) void {
    _ = self.clip_stack.pop();
    self.recalculateClip();
}

fn recalculateClip(self: *HitGrid) void {
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

fn isClipped(self: *const HitGrid, col: u16, row: u16) bool {
    if (self.clip_stack.items.len > 0 and self.current_clip == null) {
        return true;
    }

    if (self.current_clip) |clip| {
        return !clip.contains(col, row);
    }
    return false;
}

pub fn set(self: *HitGrid, col: u16, row: u16, element_num: u64) void {
    const translated = self.translatePoint(col, row) orelse return;
    if (translated.col >= self.width or translated.row >= self.height) return;
    if (self.isClipped(translated.col, translated.row)) return;

    const i = @as(usize, translated.row) * self.width + translated.col;
    self.grid[i] = element_num;
}

pub fn get(self: *const HitGrid, col: u16, row: u16) ?u64 {
    if (col >= self.width or row >= self.height) return null;
    const i = @as(usize, row) * self.width + col;
    const val = self.grid[i];
    if (val == no_hit) return null;
    return val;
}

pub fn fillRect(self: *HitGrid, x: u16, y: u16, w: u16, h: u16, element_num: u64) void {
    const end_x = @min(x + w, self.width);
    const end_y = @min(y + h, self.height);

    var row = y;
    while (row < end_y) : (row += 1) {
        var col = x;
        while (col < end_x) : (col += 1) {
            self.set(col, row, element_num);
        }
    }
}

pub fn pushOffset(self: *HitGrid, dx: i32, dy: i32) void {
    self.offset_stack.append(self.alloc, .{ .dx = dx, .dy = dy }) catch {};
    self.current_offset_x += dx;
    self.current_offset_y += dy;
}

pub fn popOffset(self: *HitGrid) void {
    if (self.offset_stack.items.len == 0) return;
    const offset = self.offset_stack.pop().?;
    self.current_offset_x -= offset.dx;
    self.current_offset_y -= offset.dy;
}

fn translatePoint(self: *const HitGrid, col: u16, row: u16) ?struct { col: u16, row: u16 } {
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

const testing = std.testing;

test "clip stack: no clip allows all writes" {
    var grid = try HitGrid.init(testing.allocator, 10, 10);
    defer grid.deinit();

    grid.set(5, 5, 42);
    try testing.expectEqual(@as(?u64, 42), grid.get(5, 5));
}

test "clip stack: single clip blocks outside writes" {
    var grid = try HitGrid.init(testing.allocator, 10, 10);
    defer grid.deinit();

    grid.pushClip(2, 2, 4, 4);

    grid.set(0, 0, 1);
    try testing.expectEqual(@as(?u64, null), grid.get(0, 0));

    grid.set(3, 3, 2);
    try testing.expectEqual(@as(?u64, 2), grid.get(3, 3));
}

test "clip stack: nested clips intersect" {
    var grid = try HitGrid.init(testing.allocator, 20, 20);
    defer grid.deinit();

    grid.pushClip(0, 0, 10, 10);
    grid.pushClip(5, 5, 10, 10);

    grid.set(3, 3, 1);
    try testing.expectEqual(@as(?u64, null), grid.get(3, 3));

    grid.set(12, 12, 2);
    try testing.expectEqual(@as(?u64, null), grid.get(12, 12));

    grid.set(7, 7, 3);
    try testing.expectEqual(@as(?u64, 3), grid.get(7, 7));
}

test "clip stack: pop restores previous clip" {
    var grid = try HitGrid.init(testing.allocator, 20, 20);
    defer grid.deinit();

    grid.pushClip(0, 0, 10, 10);
    grid.pushClip(5, 5, 10, 10);

    grid.set(3, 3, 1);
    try testing.expectEqual(@as(?u64, null), grid.get(3, 3));

    grid.popClip();

    grid.set(3, 3, 2);
    try testing.expectEqual(@as(?u64, 2), grid.get(3, 3));
}

test "clip stack: pop all restores no clipping" {
    var grid = try HitGrid.init(testing.allocator, 10, 10);
    defer grid.deinit();

    grid.pushClip(5, 5, 2, 2);

    grid.set(0, 0, 1);
    try testing.expectEqual(@as(?u64, null), grid.get(0, 0));

    grid.popClip();

    grid.set(0, 0, 2);
    try testing.expectEqual(@as(?u64, 2), grid.get(0, 0));
}

test "clip stack: fillRect respects clip" {
    var grid = try HitGrid.init(testing.allocator, 10, 10);
    defer grid.deinit();

    grid.pushClip(2, 2, 4, 4);

    grid.fillRect(0, 0, 10, 10, 42);

    try testing.expectEqual(@as(?u64, null), grid.get(0, 0));
    try testing.expectEqual(@as(?u64, null), grid.get(1, 1));
    try testing.expectEqual(@as(?u64, 42), grid.get(2, 2));
    try testing.expectEqual(@as(?u64, 42), grid.get(5, 5));
    try testing.expectEqual(@as(?u64, null), grid.get(6, 6));
}

test "offset stack translates hits and clips" {
    var grid = try HitGrid.init(testing.allocator, 5, 5);
    defer grid.deinit();

    grid.pushOffset(0, -2);
    defer grid.popOffset();

    grid.pushClip(0, 2, 1, 1);
    defer grid.popClip();

    grid.set(0, 2, 42);
    grid.set(0, 3, 99);

    try testing.expectEqual(@as(?u64, 42), grid.get(0, 0));
    try testing.expectEqual(@as(?u64, null), grid.get(0, 1));
}
