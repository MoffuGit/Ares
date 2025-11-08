const Screen = @This();

const sizepkg = @import("../size.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;

const msg = "Hello world!";

alloc: Allocator,

rows: u16,
cols: u16,

size: sizepkg.Size,

cells: ?[]u32 = null,

pub fn init(alloc: Allocator, size: sizepkg.Size) !Screen {
    const grid_size = size.grid();
    const cells_slice = try alloc.alloc(u32, msg.len);
    errdefer alloc.free(cells_slice);
    var i: usize = 0;

    var utf8 = (try std.unicode.Utf8View.init(msg)).iterator();
    while (utf8.nextCodepoint()) |codepoint| : (i += 1) {
        cells_slice[i] = @intCast(codepoint);
    }

    const some: Screen = .{
        .size = size,
        .alloc = alloc,
        .rows = grid_size.rows,
        .cols = grid_size.columns,
        .cells = cells_slice,
    };

    return some;
}

pub fn resize(self: *Screen, size: sizepkg.Size) void {
    self.size = size;
    const grid_size = self.size.grid();
    self.rows = grid_size.rows;
    self.cols = grid_size.columns;
}

pub fn deinit(self: *Screen) void {
    if (self.cells) |cells| {
        self.alloc.free(cells);
    }
}
