const Screen = @This();

const sizepkg = @import("../size.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;

const msg = "Hello world!";

alloc: Allocator,

rows: u16,
cols: u16,

size: sizepkg.Size,

cells: std.ArrayList([]u32),

rebuild_cells: bool = false,

pub fn init(alloc: Allocator, size: sizepkg.Size) !Screen {
    const grid_size = size.grid();
    const cells = try std.ArrayList([]u32).initCapacity(alloc, 0);

    return .{
        .size = size,
        .alloc = alloc,
        .rows = grid_size.rows,
        .cols = grid_size.columns,
        .cells = cells,
    };
}

pub fn resize(self: *Screen, size: sizepkg.Size) void {
    self.size = size;
    const grid_size = self.size.grid();
    self.rows = grid_size.rows;
    self.cols = grid_size.columns;
}

pub fn deinit(self: *Screen) void {
    for (self.cells.items) |line_cells| {
        self.alloc.free(line_cells);
    }
    self.cells.deinit(self.alloc);
}

pub fn resetCells(self: *Screen) void {
    self.rebuild_cells = true;

    for (self.cells.items) |line_cells| {
        self.alloc.free(line_cells);
    }

    self.cells.clearAndFree(self.alloc);
}

pub fn addNewLine(self: *Screen, line_bytes: []const u8) !void {
    self.rebuild_cells = true;

    var codepoints_list = try std.ArrayList(u32).initCapacity(self.alloc, 0);
    errdefer codepoints_list.deinit(self.alloc);

    var utf8_view = try std.unicode.Utf8View.init(line_bytes);
    var it = utf8_view.iterator();
    while (it.nextCodepoint()) |cp| {
        try codepoints_list.append(self.alloc, cp);
    }

    const new_line_slice = try codepoints_list.toOwnedSlice(self.alloc);
    errdefer self.alloc.free(new_line_slice);

    try self.cells.append(self.alloc, new_line_slice);
}
