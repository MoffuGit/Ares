const std = @import("std");
const Allocator = std.mem.Allocator;

pub const HitGrid = @This();

pub const no_hit: u64 = std.math.maxInt(u64);

grid: []u64 = &.{},
width: u16 = 0,
height: u16 = 0,

pub fn init(alloc: Allocator, width: u16, height: u16) !HitGrid {
    const size = @as(usize, width) * height;
    const grid = try alloc.alloc(u64, size);
    @memset(grid, no_hit);
    return .{
        .grid = grid,
        .width = width,
        .height = height,
    };
}

pub fn deinit(self: *HitGrid, alloc: Allocator) void {
    if (self.grid.len > 0) {
        alloc.free(self.grid);
    }
}

pub fn resize(self: *HitGrid, alloc: Allocator, width: u16, height: u16) !void {
    self.deinit(alloc);
    self.* = try HitGrid.init(alloc, width, height);
}

pub fn clear(self: *HitGrid) void {
    @memset(self.grid, no_hit);
}

pub fn set(self: *HitGrid, col: u16, row: u16, element_num: u64) void {
    if (col >= self.width or row >= self.height) return;
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
