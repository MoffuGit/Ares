const std = @import("std");
const Allocator = std.mem.Allocator;
const ClipRect = @import("ClipRect.zig");

pub const HitGrid = @This();
pub const Element = @import("element/mod.zig");

pub const no_hit: u64 = std.math.maxInt(u64);

const max_clip_depth = 8;

alloc: Allocator,

grid: []u64 = &.{},
width: u16 = 0,
height: u16 = 0,

clip_stack: std.ArrayList(ClipRect) = .{},
current_clip: ?ClipRect = null,

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
    const new_clip = ClipRect{ .x = x, .y = y, .width = w, .height = h };

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
    if (self.current_clip) |clip| {
        return !clip.contains(col, row);
    }
    return false;
}

pub fn set(self: *HitGrid, col: u16, row: u16, element_num: u64) void {
    if (col >= self.width or row >= self.height) return;
    if (self.isClipped(col, row)) return;

    const i = @as(usize, row) * self.width + col;
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

pub fn hitElement(element: *Element, self: *HitGrid) void {
    self.fillRect(element.layout.left, element.layout.top, element.layout.width, element.layout.height, element.num);
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
