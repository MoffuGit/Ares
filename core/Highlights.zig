const std = @import("std");
const Allocator = std.mem.Allocator;
const Style = @import("font/mod.zig").Style;
const zintect = @import("zintect");

pub const Span = struct {
    start: u32,
    end: u32,
    color: [4]u8,
    style: Style = .regular,
};

pub const Highlights = @This();

lines: [][]Span = &.{},

pub fn deinit(self: *Highlights, alloc: Allocator) void {
    for (self.lines) |line| {
        if (line.len > 0) alloc.free(line);
    }
    if (self.lines.len > 0) alloc.free(self.lines);
    self.* = .{};
}

pub fn visibleLines(self: *const Highlights, scroll_row: u64, max_rows: usize) []const []Span {
    const start = @min(std.math.cast(usize, scroll_row) orelse self.lines.len, self.lines.len);
    const count = @min(max_rows, self.lines.len - start);
    return self.lines[start .. start + count];
}
