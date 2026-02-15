const std = @import("std");
const vaxis = @import("vaxis");
const unicode = vaxis.unicode;

const assert = std.debug.assert;

const Key = vaxis.Key;
const Cell = vaxis.Cell;
const Window = @import("../mod.zig");

const GapBuffer = @import("../../../datastruct/gap_buffer.zig").GapBuffer(u8);

const TextInput = @This();

/// The events that this widget handles
const Event = union(enum) {
    key_press: Key,
};

const ellipsis: Cell.Character = .{ .grapheme = "…", .width = 1 };

// Index of our cursor
buf: GapBuffer,

/// the number of graphemes to skip when drawing. Used for horizontal scrolling
draw_offset: u16 = 0,
/// the column we placed the cursor the last time we drew
prev_cursor_col: u16 = 0,
/// the grapheme index of the cursor the last time we drew
prev_cursor_idx: u16 = 0,
/// approximate distance from an edge before we scroll
scroll_offset: u16 = 4,

pub fn init(alloc: std.mem.Allocator) TextInput {
    return TextInput{
        .buf = GapBuffer.init(alloc),
    };
}

pub fn deinit(self: *TextInput) void {
    self.buf.deinit();
}

pub fn update(self: *TextInput, event: Event) !void {
    switch (event) {
        .key_press => |key| {
            if (key.matches(Key.backspace, .{})) {
                self.deleteBeforeCursor();
            } else if (key.matches(Key.delete, .{}) or key.matches('d', .{ .ctrl = true })) {
                self.deleteAfterCursor();
            } else if (key.matches(Key.left, .{}) or key.matches('b', .{ .ctrl = true })) {
                self.cursorLeft();
            } else if (key.matches(Key.right, .{}) or key.matches('f', .{ .ctrl = true })) {
                self.cursorRight();
            } else if (key.matches('a', .{ .ctrl = true }) or key.matches(Key.home, .{})) {
                self.buf.moveGapLeft(self.buf.firstHalf().len);
            } else if (key.matches('e', .{ .ctrl = true }) or key.matches(Key.end, .{})) {
                self.buf.moveGapRight(self.buf.secondHalf().len);
            } else if (key.matches('k', .{ .ctrl = true })) {
                self.deleteToEnd();
            } else if (key.matches('u', .{ .ctrl = true })) {
                self.deleteToStart();
            } else if (key.matches('b', .{ .alt = true }) or key.matches(Key.left, .{ .alt = true })) {
                self.moveBackwardWordwise();
            } else if (key.matches('f', .{ .alt = true }) or key.matches(Key.right, .{ .alt = true })) {
                self.moveForwardWordwise();
            } else if (key.matches('w', .{ .ctrl = true }) or key.matches(Key.backspace, .{ .alt = true })) {
                self.deleteWordBefore();
            } else if (key.matches('d', .{ .alt = true })) {
                self.deleteWordAfter();
            } else if (key.text) |text| {
                try self.insertSliceAtCursor(text);
            }
        },
    }
}

/// insert text at the cursor position
pub fn insertSliceAtCursor(self: *TextInput, data: []const u8) std.mem.Allocator.Error!void {
    var iter = unicode.graphemeIterator(data);
    while (iter.next()) |text| {
        try self.buf.insertSliceAtCursor(text.bytes(data));
    }
}

pub fn sliceToCursor(self: *TextInput, buf: []u8) []const u8 {
    assert(buf.len >= self.buf.cursor);
    @memcpy(buf[0..self.buf.cursor], self.buf.firstHalf());
    return buf[0..self.buf.cursor];
}

/// calculates the display width from the draw_offset to the cursor
pub fn widthToCursor(self: *TextInput, win: Window) u16 {
    var width: u16 = 0;
    const first_half = self.buf.firstHalf();
    var first_iter = unicode.graphemeIterator(first_half);
    var i: usize = 0;
    while (first_iter.next()) |grapheme| {
        defer i += 1;
        if (i < self.draw_offset) {
            continue;
        }
        const g = grapheme.bytes(first_half);
        width += win.gwidth(g);
    }
    return width;
}

pub fn cursorLeft(self: *TextInput) void {
    // We need to find the size of the last grapheme in the first half
    var iter = unicode.graphemeIterator(self.buf.firstHalf());
    var len: usize = 0;
    while (iter.next()) |grapheme| {
        len = grapheme.len;
    }
    self.buf.moveGapLeft(len);
}

pub fn cursorRight(self: *TextInput) void {
    var iter = unicode.graphemeIterator(self.buf.secondHalf());
    const grapheme = iter.next() orelse return;
    self.buf.moveGapRight(grapheme.len);
}

pub fn graphemesBeforeCursor(self: *const TextInput) u16 {
    const first_half = self.buf.firstHalf();
    var first_iter = unicode.graphemeIterator(first_half);
    var i: u16 = 0;
    while (first_iter.next()) |_| {
        i += 1;
    }
    return i;
}

pub fn draw(self: *TextInput, win: Window) void {
    self.drawWithStyle(win, .{});
}

pub fn drawWithStyle(self: *TextInput, win: Window, style: Cell.Style) void {
    const cursor_idx = self.graphemesBeforeCursor();
    if (cursor_idx < self.draw_offset) self.draw_offset = cursor_idx;
    if (win.width == 0) return;
    while (true) {
        const width = self.widthToCursor(win);
        if (width >= win.width) {
            self.draw_offset +|= width - win.width + 1;
            continue;
        } else break;
    }

    self.prev_cursor_idx = cursor_idx;
    self.prev_cursor_col = 0;

    // assumption!! the gap is never within a grapheme
    // one way to _ensure_ this is to move the gap... but that's a cost we probably don't want to pay.
    const first_half = self.buf.firstHalf();
    var first_iter = unicode.graphemeIterator(first_half);
    var col: u16 = 0;
    var i: u16 = 0;
    while (first_iter.next()) |grapheme| {
        if (i < self.draw_offset) {
            i += 1;
            continue;
        }
        const g = grapheme.bytes(first_half);
        const w = win.gwidth(g);
        if (col + w >= win.width) {
            win.writeCell(win.width - 1, 0, .{
                .char = ellipsis,
                .style = style,
            });
            break;
        }
        win.writeCell(col, 0, .{
            .char = .{
                .grapheme = g,
                .width = @intCast(w),
            },
            .style = style,
        });
        col += w;
        i += 1;
        if (i == cursor_idx) self.prev_cursor_col = col;
    }
    const second_half = self.buf.secondHalf();
    var second_iter = unicode.graphemeIterator(second_half);
    while (second_iter.next()) |grapheme| {
        if (i < self.draw_offset) {
            i += 1;
            continue;
        }
        const g = grapheme.bytes(second_half);
        const w = win.gwidth(g);
        if (col + w > win.width) {
            win.writeCell(win.width - 1, 0, .{
                .char = ellipsis,
                .style = style,
            });
            break;
        }
        win.writeCell(col, 0, .{
            .char = .{
                .grapheme = g,
                .width = @intCast(w),
            },
            .style = style,
        });
        col += w;
        i += 1;
        if (i == cursor_idx) self.prev_cursor_col = col;
    }
    if (self.draw_offset > 0) {
        win.writeCell(0, 0, .{
            .char = ellipsis,
            .style = style,
        });
    }
    win.showCursor(self.prev_cursor_col, 0);
}

pub fn clearAndFree(self: *TextInput) void {
    self.buf.clearAndFree();
    self.reset();
}

pub fn clearRetainingCapacity(self: *TextInput) void {
    self.buf.clearRetainingCapacity();
    self.reset();
}

pub fn toOwnedSlice(self: *TextInput) ![]const u8 {
    defer self.reset();
    return self.buf.toOwnedSlice();
}

pub fn reset(self: *TextInput) void {
    self.draw_offset = 0;
    self.prev_cursor_col = 0;
    self.prev_cursor_idx = 0;
}

// returns the number of bytes before the cursor
pub fn byteOffsetToCursor(self: TextInput) usize {
    return self.buf.cursor;
}

pub fn deleteToEnd(self: *TextInput) void {
    self.buf.growGapRight(self.buf.secondHalf().len);
}

pub fn deleteToStart(self: *TextInput) void {
    self.buf.growGapLeft(self.buf.cursor);
}

pub fn deleteBeforeCursor(self: *TextInput) void {
    // We need to find the size of the last grapheme in the first half
    var iter = unicode.graphemeIterator(self.buf.firstHalf());
    var len: usize = 0;
    while (iter.next()) |grapheme| {
        len = grapheme.len;
    }
    self.buf.growGapLeft(len);
}

pub fn deleteAfterCursor(self: *TextInput) void {
    var iter = unicode.graphemeIterator(self.buf.secondHalf());
    const grapheme = iter.next() orelse return;
    self.buf.growGapRight(grapheme.len);
}

/// Moves the cursor backward by words. If the character before the cursor is a space, the cursor is
/// positioned just after the next previous space
pub fn moveBackwardWordwise(self: *TextInput) void {
    const trimmed = std.mem.trimRight(u8, self.buf.firstHalf(), " ");
    const idx = if (std.mem.lastIndexOfScalar(u8, trimmed, ' ')) |last|
        last + 1
    else
        0;
    self.buf.moveGapLeft(self.buf.cursor - idx);
}

pub fn moveForwardWordwise(self: *TextInput) void {
    const second_half = self.buf.secondHalf();
    var i: usize = 0;
    while (i < second_half.len and second_half[i] == ' ') : (i += 1) {}
    const idx = std.mem.indexOfScalarPos(u8, second_half, i, ' ') orelse second_half.len;
    self.buf.moveGapRight(idx);
}

pub fn deleteWordBefore(self: *TextInput) void {
    // Store current cursor position. Move one word backward. Delete after the cursor the bytes we
    // moved
    const pre = self.buf.cursor;
    self.moveBackwardWordwise();
    self.buf.growGapRight(pre - self.buf.cursor);
}

pub fn deleteWordAfter(self: *TextInput) void {
    // Store current cursor position. Move one word backward. Delete after the cursor the bytes we
    // moved
    const second_half = self.buf.secondHalf();
    var i: usize = 0;
    while (i < second_half.len and second_half[i] == ' ') : (i += 1) {}
    const idx = std.mem.indexOfScalarPos(u8, second_half, i, ' ') orelse second_half.len;
    self.buf.growGapRight(idx);
}

test "assertion" {
    const astronaut = "👩‍🚀";
    const astronaut_emoji: Key = .{
        .text = astronaut,
        .codepoint = try std.unicode.utf8Decode(astronaut[0..4]),
    };
    var input = TextInput.init(std.testing.allocator);
    defer input.deinit();
    for (0..6) |_| {
        try input.update(.{ .key_press = astronaut_emoji });
    }
}

test "sliceToCursor" {
    var input = init(std.testing.allocator);
    defer input.deinit();
    try input.insertSliceAtCursor("hello, world");
    input.cursorLeft();
    input.cursorLeft();
    input.cursorLeft();
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("hello, wo", input.sliceToCursor(&buf));
    input.cursorRight();
    try std.testing.expectEqualStrings("hello, wor", input.sliceToCursor(&buf));
}
