const std = @import("std");
const Allocator = std.mem.Allocator;
const GapBuffer = @import("datastruct").GapBuffer;

pub const TextBuffer = @This();

alloc: Allocator,
content: GapBuffer(u8),
layout: Layout = .{},
version: usize = 0,

pub fn init(alloc: Allocator) TextBuffer {
    return .{
        .alloc = alloc,
        .content = GapBuffer(u8).init(alloc),
    };
}

pub fn rows(self: *const TextBuffer) usize {
    return self.layout.rows.len;
}

pub fn initFromBytes(alloc: Allocator, raw: []const u8) !TextBuffer {
    var content = try GapBuffer(u8).initCapacity(alloc, raw.len);
    content.appendSliceBeforeAssumeCapacity(raw);

    var text = TextBuffer.init(alloc);
    text.content = content;
    try text.rebuildDerivedState();
    return text;
}

pub fn deinit(self: *TextBuffer) void {
    self.layout.deinit(self.alloc);
    self.content.deinit();
    self.* = undefined;
}

pub fn rebuildDerivedState(self: *TextBuffer) !void {
    try self.layout.rebuild(self.alloc, self.content);
}

pub fn insertUtf8At(self: *TextBuffer, row: usize, col: usize, raw_bytes: []const u8) !void {
    const raw = try self.content.dupeLogicalSlice(self.alloc, 0, self.content.realLength());
    defer self.alloc.free(raw);

    const offset = try byteOffsetForPosition(raw, row, col);
    try self.content.replaceRangeBefore(offset, 0, raw_bytes);
    try self.rebuildDerivedState();

    self.version += 1;
}

pub fn backspaceAt(self: *TextBuffer, row: usize, col: usize) !bool {
    const raw = try self.content.dupeLogicalSlice(self.alloc, 0, self.content.realLength());
    defer self.alloc.free(raw);

    const cursor_offset = try byteOffsetForPosition(raw, row, col);
    if (cursor_offset == 0) return false;

    const start = previousScalarStart(raw, cursor_offset);
    try self.content.replaceRangeBefore(start, cursor_offset - start, &.{});
    try self.rebuildDerivedState();

    self.version += 1;

    return true;
}

pub fn deleteAt(self: *TextBuffer, row: usize, col: usize) !bool {
    const raw = try self.content.dupeLogicalSlice(self.alloc, 0, self.content.realLength());
    defer self.alloc.free(raw);

    const offset = try byteOffsetForPosition(raw, row, col);
    if (offset >= raw.len) return false;

    const len = if (raw[offset] == '\n') 1 else std.unicode.utf8ByteSequenceLength(raw[offset]) catch return false;
    try self.content.replaceRangeBefore(offset, len, &.{});
    try self.rebuildDerivedState();

    self.version += 1;

    return true;
}

pub fn visibleRows(self: *const TextBuffer, scroll_row: u64, max_rows: usize) []const Row {
    return self.layout.visibleRows(scroll_row, max_rows);
}

test "text version increments when content changes" {
    var text = TextBuffer.init(std.testing.allocator);
    defer text.deinit();

    try std.testing.expectEqual(@as(u64, 0), text.version);

    try text.insertUtf8At(0, 0, "hi");
    try std.testing.expectEqual(@as(u64, 1), text.version);

    try std.testing.expect(try text.backspaceAt(0, 2));
    try std.testing.expectEqual(@as(u64, 2), text.version);
}

fn byteOffsetForPosition(raw: []const u8, target_row: usize, target_col: usize) !usize {
    var row: usize = 0;
    var col: usize = 0;
    var offset: usize = 0;

    while (offset < raw.len) {
        if (row == target_row and col >= target_col) return offset;

        if (raw[offset] == '\n') {
            if (row == target_row) return offset;
            row += 1;
            col = 0;
            offset += 1;
            continue;
        }

        const len = std.unicode.utf8ByteSequenceLength(raw[offset]) catch return error.InvalidUtf8;
        if (offset + len > raw.len) return error.InvalidUtf8;

        offset += len;
        col += 1;
    }

    return raw.len;
}

fn previousScalarStart(raw: []const u8, offset: usize) usize {
    var idx = offset - 1;
    while (idx > 0 and isUtf8ContinuationByte(raw[idx])) {
        idx -= 1;
    }
    return idx;
}

fn isUtf8ContinuationByte(byte: u8) bool {
    return (byte & 0b1100_0000) == 0b1000_0000;
}

fn decodeUtf8Line(alloc: Allocator, raw_bytes: []const u8) ![]u32 {
    var codepoints = try std.ArrayList(u32).initCapacity(alloc, 0);
    errdefer codepoints.deinit(alloc);

    const view = std.unicode.Utf8View.initUnchecked(raw_bytes);
    var it = view.iterator();
    while (it.nextCodepoint()) |cp| {
        try codepoints.append(alloc, cp);
    }

    return codepoints.toOwnedSlice(alloc);
}
pub const Row = struct {
    codepoints: []u32,

    pub fn deinit(self: *Row, alloc: Allocator) void {
        if (self.codepoints.len > 0) {
            alloc.free(self.codepoints);
        }
        self.* = undefined;
    }
};

pub const Layout = struct {
    rows: []Row = &.{},

    pub fn deinit(self: *Layout, alloc: Allocator) void {
        for (self.rows) |*row| {
            row.deinit(alloc);
        }
        if (self.rows.len > 0) {
            alloc.free(self.rows);
        }
        self.rows = &.{};
    }

    pub fn rebuild(self: *Layout, alloc: Allocator, content: GapBuffer(u8)) !void {
        self.deinit(alloc);

        var new_rows = try std.ArrayList(Row).initCapacity(alloc, 0);
        errdefer {
            for (new_rows.items) |*row| {
                row.deinit(alloc);
            }
            new_rows.deinit(alloc);
        }

        var line_bytes = try std.ArrayList(u8).initCapacity(alloc, 0);
        defer line_bytes.deinit(alloc);

        try appendRowsFromBytes(alloc, &new_rows, &line_bytes, content.items);
        try appendRowsFromBytes(alloc, &new_rows, &line_bytes, content.secondHalf());
        try appendDecodedRow(alloc, &new_rows, line_bytes.items);

        self.rows = try new_rows.toOwnedSlice(alloc);
    }

    pub fn visibleRows(self: *const Layout, scroll_row: u64, max_rows: usize) []const Row {
        const start = @min(std.math.cast(usize, scroll_row) orelse self.rows.len, self.rows.len);
        const count = @min(max_rows, self.rows.len - start);
        return self.rows[start .. start + count];
    }

    fn appendRowsFromBytes(
        alloc: Allocator,
        new_rows: *std.ArrayList(Row),
        line_bytes: *std.ArrayList(u8),
        raw_bytes: []const u8,
    ) !void {
        var start: usize = 0;
        for (raw_bytes, 0..) |byte, idx| {
            if (byte != '\n') continue;

            try line_bytes.appendSlice(alloc, raw_bytes[start..idx]);
            try appendDecodedRow(alloc, new_rows, line_bytes.items);
            line_bytes.clearRetainingCapacity();
            start = idx + 1;
        }

        try line_bytes.appendSlice(alloc, raw_bytes[start..]);
    }

    fn appendDecodedRow(
        alloc: Allocator,
        new_rows: *std.ArrayList(Row),
        row_bytes: []const u8,
    ) !void {
        try new_rows.append(alloc, .{ .codepoints = try decodeUtf8Line(alloc, row_bytes) });
    }
};
