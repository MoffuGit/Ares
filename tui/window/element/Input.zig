const std = @import("std");
const vaxis = @import("vaxis");
const unicode = vaxis.unicode;
const datastruct = @import("datastruct");
const gwidth = vaxis.gwidth.gwidth;

const assert = std.debug.assert;

const Key = vaxis.Key;
const Cell = vaxis.Cell;
const Element = @import("mod.zig");
const ElementEvent = Element.ElementEvent;

const HitGrid = @import("../HitGrid.zig");

const InputElement = @import("TypedElement.zig").TypedElement(Input);
const GapBuffer = datastruct.GapBuffer(u8);

const Input = @This();

buf: GapBuffer,
element: InputElement,
multiline: bool,

cursor_col: u16 = 0,
cursor_row: u16 = 0,

pub const Options = struct {
    element: InputElement.Options = .{},
    multiline: bool = false,
};

pub fn create(alloc: std.mem.Allocator, comptime callbacks: InputElement.Callbacks, opts: Options) !*Input {
    const input = try alloc.create(Input);
    errdefer alloc.destroy(input);

    const merged: InputElement.Callbacks = .{
        .drawFn = callbacks.drawFn,
        .beforeDrawFn = callbacks.beforeDrawFn,
        .afterDrawFn = callbacks.afterDrawFn,
        .hitFn = callbacks.hitFn orelse hitFn,
        .beforeHitFn = callbacks.beforeHitFn,
        .afterHitFn = callbacks.afterHitFn,
        .updateFn = callbacks.updateFn,
    };

    input.* = .{
        .buf = GapBuffer.init(alloc),
        .multiline = opts.multiline,
        .element = InputElement.init(
            alloc,
            input,
            merged,
            opts.element,
        ),
    };

    try input.element.on(.key_press, onKeyPress);
    try input.element.on(.click, onClick);

    return input;
}

pub fn destroy(self: *Input) void {
    const alloc = self.buf.allocator;
    self.element.deinit();
    self.buf.deinit();
    alloc.destroy(self);
}

pub fn cursorPos(self: *const Input) usize {
    return self.buf.items.len;
}

pub fn contentLength(self: *const Input) usize {
    return self.buf.realLength();
}

pub fn elem(self: *Input) *Element.Element {
    return self.element.elem();
}

// ---- Cursor movement ----

pub fn cursorLeft(self: *Input) void {
    if (self.buf.items.len == 0) return;
    const last_grapheme_len = lastGraphemeLen(self.buf.items);
    self.buf.moveGap(self.buf.items.len - last_grapheme_len);
    self.updateCursorFromGap();
}

pub fn cursorRight(self: *Input) void {
    const second = self.buf.secondHalf();
    if (second.len == 0) return;
    const first_grapheme_len = firstGraphemeLen(second);
    self.buf.moveGap(self.buf.items.len + first_grapheme_len);
    self.updateCursorFromGap();
}

pub fn cursorUp(self: *Input) void {
    if (!self.multiline) return;
    const col = self.colInCurrentLine();
    self.moveToLineStart();
    if (self.buf.items.len == 0) return;
    // Move past the '\n' to end of previous line
    self.buf.moveGap(self.buf.items.len - 1);
    self.moveToLineStart();
    self.moveForwardByCol(col);
    self.updateCursorFromGap();
}

pub fn cursorDown(self: *Input) void {
    if (!self.multiline) return;
    const col = self.colInCurrentLine();
    const second = self.buf.secondHalf();
    const newline_pos = std.mem.indexOfScalar(u8, second, '\n') orelse return;
    self.buf.moveGap(self.buf.items.len + newline_pos + 1);
    self.moveForwardByCol(col);
    self.updateCursorFromGap();
}

pub fn cursorHome(self: *Input) void {
    self.moveToLineStart();
    self.updateCursorFromGap();
}

pub fn cursorEnd(self: *Input) void {
    const second = self.buf.secondHalf();
    const newline_pos = std.mem.indexOfScalar(u8, second, '\n') orelse second.len;
    self.buf.moveGap(self.buf.items.len + newline_pos);
    self.updateCursorFromGap();
}

// ---- Editing ----

pub fn insertChar(self: *Input, text: []const u8) !void {
    if (!self.multiline and std.mem.indexOfScalar(u8, text, '\n') != null) return;
    try self.buf.appendSliceBefore(text);
    self.updateCursorFromGap();
}

pub fn deleteBack(self: *Input) void {
    if (self.buf.items.len == 0) return;
    const len = lastGraphemeLen(self.buf.items);
    self.buf.items.len -= len;
    self.updateCursorFromGap();
}

pub fn deleteForward(self: *Input) void {
    const second = self.buf.secondHalf();
    if (second.len == 0) return;
    const len = firstGraphemeLen(second);
    self.buf.second_start += len;
    self.requestDraw();
}

// ---- Event handlers ----

fn onKeyPress(self: *Input, data: ElementEvent) void {
    const key = data.event.key_press;

    if (key.codepoint == Key.backspace) {
        self.deleteBack();
        return;
    }

    if (key.codepoint == Key.delete) {
        self.deleteForward();
        return;
    }

    if (key.codepoint == Key.left) {
        self.cursorLeft();
        return;
    }

    if (key.codepoint == Key.right) {
        self.cursorRight();
        return;
    }

    if (key.codepoint == Key.up) {
        self.cursorUp();
        return;
    }

    if (key.codepoint == Key.down) {
        self.cursorDown();
        return;
    }

    if (key.codepoint == Key.home) {
        self.cursorHome();
        return;
    }

    if (key.codepoint == Key.end) {
        self.cursorEnd();
        return;
    }

    if (key.text) |text| {
        self.insertChar(text) catch return;
        return;
    }
}

fn onClick(self: *Input, evt: ElementEvent) void {
    const mouse = evt.event.click;
    const layout = evt.element.layout;

    const click_col = mouse.col -| layout.left;
    const click_row = mouse.row -| layout.top;

    self.moveCursorToPosition(click_col, click_row);
}

fn hitFn(_: *Input, element: *Element.Element, hit_grid: *HitGrid) void {
    element.hitSelf(hit_grid);
}

// ---- Internal helpers ----

fn firstGraphemeLen(str: []const u8) usize {
    var iter = unicode.graphemeIterator(str);
    const grapheme = iter.next() orelse return 0;
    return grapheme.len;
}

fn lastGraphemeLen(str: []const u8) usize {
    var iter = unicode.graphemeIterator(str);
    var last_len: usize = 0;
    while (iter.next()) |grapheme| {
        last_len = grapheme.len;
    }
    return last_len;
}

pub fn moveCursorToPosition(self: *Input, target_col: u16, target_row: u16) void {
    self.buf.moveGap(0);
    const content = self.buf.secondHalf();

    var row: u16 = 0;
    var col: u16 = 0;
    var byte_pos: usize = 0;

    var iter = unicode.graphemeIterator(content);
    while (iter.next()) |grapheme| {
        if (row == target_row and col >= target_col) break;
        if (row > target_row) break;

        const s = grapheme.bytes(content);
        if (std.mem.eql(u8, s, "\n")) {
            if (row == target_row) break;
            row += 1;
            col = 0;
            byte_pos = grapheme.start + grapheme.len;
            continue;
        }

        const w: u16 = @intCast(gwidth(s, .unicode));
        col += w;
        byte_pos = grapheme.start + grapheme.len;
    }

    self.buf.moveGap(byte_pos);
    self.cursor_col = col;
    self.cursor_row = row;
}

fn moveToLineStart(self: *Input) void {
    const before = self.buf.items;
    if (before.len == 0) return;
    // Find last '\n' in before-gap content
    if (std.mem.lastIndexOfScalar(u8, before, '\n')) |nl_pos| {
        self.buf.moveGap(nl_pos + 1);
    } else {
        self.buf.moveGap(0);
    }
}

fn moveForwardByCol(self: *Input, target_col: u16) void {
    const second = self.buf.secondHalf();
    var col: u16 = 0;
    var advance: usize = 0;

    var iter = unicode.graphemeIterator(second);
    while (iter.next()) |grapheme| {
        if (col >= target_col) break;
        const s = grapheme.bytes(second);
        if (std.mem.eql(u8, s, "\n")) break;
        const w: u16 = @intCast(gwidth(s, .unicode));
        col += w;
        advance = grapheme.start + grapheme.len;
    }

    if (advance > 0) {
        self.buf.moveGap(self.buf.items.len + advance);
    }
}

fn colInCurrentLine(self: *const Input) u16 {
    const before = self.buf.items;
    if (before.len == 0) return 0;

    const line_start = if (std.mem.lastIndexOfScalar(u8, before, '\n')) |nl_pos|
        nl_pos + 1
    else
        0;

    const line = before[line_start..];
    var col: u16 = 0;
    var iter = unicode.graphemeIterator(line);
    while (iter.next()) |grapheme| {
        const s = grapheme.bytes(line);
        const w: u16 = @intCast(gwidth(s, .unicode));
        col += w;
    }
    return col;
}

fn updateCursorFromGap(self: *Input) void {
    var col: u16 = 0;
    var row: u16 = 0;
    const before = self.buf.items;

    var iter = unicode.graphemeIterator(before);
    while (iter.next()) |grapheme| {
        const s = grapheme.bytes(before);
        if (std.mem.eql(u8, s, "\n")) {
            row += 1;
            col = 0;
        } else {
            const w: u16 = @intCast(gwidth(s, .unicode));
            col += w;
        }
    }
    self.cursor_col = col;
    self.cursor_row = row;
    self.requestDraw();
}

fn requestDraw(self: *Input) void {
    if (self.element.elem().context) |ctx| ctx.requestDraw();
}
