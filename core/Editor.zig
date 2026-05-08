const Editor = @This();

const std = @import("std");
const globalpkg = @import("global.zig");
const global = &globalpkg.state;
const Allocator = std.mem.Allocator;
const inputpkg = @import("input.zig");
const Project = @import("Project.zig");
const Buffer = @import("Buffer.zig");
const TextBuffer = @import("Text.zig");
const Renderer = @import("Renderer.zig");
const fontpkg = @import("font/mod.zig");
const Style = fontpkg.Style;
const sizepkg = @import("size.zig");
const shaderpkg = Renderer.GraphicsAPI.shaders;
const Settings = @import("settings/mod.zig");
const Modifiers = @import("keymaps/KeyStroke.zig").Modifiers;

const log = std.log.scoped(.editor);

pub const CursorPosition = struct {
    row: u64 = 0,
    col: u64 = 0,
};

pub const SavedPosition = struct {
    scroll_row: u64 = 0,
    cursor: CursorPosition = .{},
};

mutex: std.Thread.Mutex = .{},
project: *Project,
alloc: Allocator,
settings: *Settings,
id: u64,

buffer: ?*Buffer = null,
entry_id: ?u64 = null,
scroll_row: u64 = 0,
cursor: CursorPosition = .{},
saved_positions: std.AutoHashMapUnmanaged(u64, SavedPosition) = .{},
rebuild_cells: bool = false,
color: [4]u8,
gutter_color: [4]u8,
bg_color: [4]u8,
accent_color: [4]u8,

size: sizepkg.Size,

pub fn init(
    alloc: Allocator,
    id: u64,
    project: *Project,
    settings: *Settings,
    size: sizepkg.Size,
) Editor {
    return .{
        .alloc = alloc,
        .id = id,
        .project = project,
        .size = size,
        .settings = settings,
        .color = settings.getColor(.fg),
        .gutter_color = settings.getColor(.gutter),
        .bg_color = settings.getColor(.mutedBg),
        .accent_color = settings.getColor(.accent),
    };
}

pub fn deinit(self: *Editor) void {
    self.saved_positions.deinit(self.alloc);
}

pub fn selectEntry(self: *Editor, id: u64) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    if (self.buffer) |curr| {
        if (curr.id == id) return;
    }

    if (self.project.openBuffer(id)) |buffer| {
        if (self.entry_id) |prev_id| {
            self.saved_positions.put(self.alloc, prev_id, .{
                .scroll_row = self.scroll_row,
                .cursor = self.cursor,
            }) catch {};
        }

        self.buffer = buffer;
        self.entry_id = id;

        if (self.saved_positions.get(id)) |saved| {
            self.scroll_row = saved.scroll_row;
            self.cursor = saved.cursor;
        } else {
            self.scroll_row = 0;
            self.cursor = .{};
        }
        self.clampCursor();
        self.ensureCursorVisible();

        self.rebuild_cells = true;

        self.emitUpdate();
    }
}

pub fn scroll(self: *Editor, row: u64) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    self.scroll_row = row;
    self.rebuild_cells = true;
}

pub fn setCursorPosition(self: *Editor, row: u64, col: u64) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    self.cursor = .{ .row = row, .col = col };
    self.clampCursor();
    self.ensureCursorVisible();

    self.emitUpdate();

    self.rebuild_cells = true;
}

fn clampCursor(self: *Editor) void {
    const buffer = self.buffer orelse {
        self.cursor = .{};
        return;
    };

    const row_count = buffer.rows();
    if (row_count == 0) {
        self.cursor = .{};
        return;
    }

    const max_row: u64 = @intCast(row_count - 1);
    if (self.cursor.row > max_row) self.cursor.row = max_row;

    const col_count: u64 = @intCast(buffer.getColsCountAt(@intCast(self.cursor.row)));
    if (self.cursor.col > col_count) self.cursor.col = col_count;
}

/// Adjust scroll_row so the cursor stays inside the visible area.
fn ensureCursorVisible(self: *Editor) void {
    if (self.size.cell.height == 0) return;

    // Fully visible rows (floor); bottom row may be partially visible due to
    // @ceil in GridSize, so we use floor to keep the cursor entirely on screen.
    const visible_rows: u64 = @max(1, self.size.screen.height / self.size.cell.height);

    if (self.cursor.row < self.scroll_row) {
        self.scroll_row = self.cursor.row;
        self.rebuild_cells = true;
    } else if (self.cursor.row >= self.scroll_row + visible_rows) {
        self.scroll_row = self.cursor.row - visible_rows + 1;
        self.rebuild_cells = true;
    }
}

pub fn keyEvent(self: *Editor, event: inputpkg.KeyEvent) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    if (hasCommandModifiers(event.mods)) return;
    if (self.buffer == null or self.buffer.?.getState() != .ready) return;

    const changed = switch (event.input) {
        .text => |cp| self.insertCodepoint(cp),
        .enter => self.insertAscii('\n', .{ .row = self.cursor.row + 1, .col = 0 }),
        .tab => self.insertAscii('\t', .{ .row = self.cursor.row, .col = self.cursor.col + 1 }),
        .backspace => self.backspace(),
        .delete => self.delete(),
    };

    if (!changed) return;

    self.clampCursor();
    self.ensureCursorVisible();

    self.emitUpdate();
}

pub fn resize(self: *Editor, size: sizepkg.Size) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    self.size = size;
    self.ensureCursorVisible();
    self.rebuild_cells = true;
}

pub fn mouseButton(self: *Editor, evt: inputpkg.MouseButtonEvent) void {
    if (evt.button != .left or evt.action != .release) return;

    self.mutex.lock();
    defer self.mutex.unlock();

    const buffer = self.buffer orelse return;

    const cell_width: f64 = @floatFromInt(self.size.cell.width);
    const cell_height: f64 = @floatFromInt(self.size.cell.height);

    const raw_col: u64 = if (evt.x >= 0) @intFromFloat(evt.x / cell_width) else 0;
    const row: u64 = if (evt.y >= 0) @intFromFloat(evt.y / cell_height) else 0;

    const gutter_width: u64 = @intCast(lineNumberGutterWidth(buffer.rows()));
    const col = raw_col -| gutter_width;

    self.cursor = .{ .row = self.scroll_row + row, .col = col };
    self.clampCursor();
    self.ensureCursorVisible();

    self.emitUpdate();

    self.rebuild_cells = true;
}

pub fn mouseMove(_: *Editor, _: inputpkg.MouseMoveEvent) void {}

pub fn onBufferUpdate(self: *Editor, entry_id: u64) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    if (self.buffer != null and self.buffer.?.id != entry_id) return;

    self.clampCursor();
    self.ensureCursorVisible();

    self.emitUpdate();

    self.rebuild_cells = true;
}

pub fn readEditorState(self: *Editor, out: *globalpkg.ExternEditorState) bool {
    self.mutex.lock();
    defer self.mutex.unlock();

    const buffer = self.buffer orelse return false;
    if (buffer.getState() != .ready) return false;

    const rows = buffer.rows();

    out.* = .{
        .surface_id = self.id,
        .entry_id = buffer.id,
        .row_count = rows,
        .scroll_row = self.scroll_row,
        .cursor_row = self.cursor.row,
        .cursor_col = self.cursor.col,
    };

    return true;
}

fn emitUpdate(self: *Editor) void {
    const buffer = self.buffer orelse return;
    const entry_id = self.entry_id orelse return;

    _ = global.emit(.{ .editorUpdate = .{
        .surface_id = self.id,
        .entry_id = entry_id,
        .row_count = buffer.rows(),
        .scroll_row = self.scroll_row,
        .cursor_row = self.cursor.row,
        .cursor_col = self.cursor.col,
    } }, .instant);
}

fn insertCodepoint(self: *Editor, cp: u21) bool {
    var utf8: [4]u8 = undefined;
    const len = std.unicode.utf8Encode(cp, &utf8) catch return false;

    return self.insertBytes(utf8[0..len], .{ .row = self.cursor.row, .col = self.cursor.col + 1 });
}

fn insertAscii(self: *Editor, byte: u8, next_cursor: CursorPosition) bool {
    var raw = [1]u8{byte};
    return self.insertBytes(&raw, next_cursor);
}

fn insertBytes(self: *Editor, bytes: []const u8, next_cursor: CursorPosition) bool {
    if (self.buffer) |buffer| {
        buffer.insertUtf8At(@intCast(self.cursor.row), @intCast(self.cursor.col), bytes) catch return false;
        self.cursor = next_cursor;

        return true;
    }

    return false;
}
fn backspace(self: *Editor) bool {
    const buffer = self.buffer orelse return false;

    if (self.cursor.row == 0 and self.cursor.col == 0) return false;

    if (self.cursor.col > 0) {
        if (!(buffer.backspaceAt(@intCast(self.cursor.row), @intCast(self.cursor.col)) catch return false)) return false;
        self.cursor.col -= 1;
    } else {
        const previous_row = self.cursor.row - 1;
        const previous_col = if (previous_row < buffer.text.layout.rows.len)
            buffer.getColsCountAt(@intCast(previous_row))
        else
            0;
        if (!(buffer.backspaceAt(@intCast(self.cursor.row), @intCast(self.cursor.col)) catch return false)) return false;
        self.cursor = .{ .row = previous_row, .col = previous_col };
    }

    return true;
}

fn delete(self: *Editor) bool {
    const buffer = self.buffer orelse return false;
    return buffer.deleteAt(@intCast(self.cursor.row), @intCast(self.cursor.col)) catch return false;
}

fn hasCommandModifiers(mods: Modifiers) bool {
    return mods.alt or mods.ctrl or mods.super or mods.hyper or mods.meta;
}

pub fn frameCallback(self: *Editor, renderer: *Renderer) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    const buffer = self.buffer orelse return;
    if (buffer.getState() != .ready) return;
    if (!self.rebuild_cells) return;

    var arena = std.heap.ArenaAllocator.init(renderer.alloc);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const grid = renderer.size.grid();

    const snap = try buffer.snapshot(arena_alloc, self.scroll_row, grid.rows);

    try rebuildCells(
        renderer,
        arena_alloc,
        snap.rows,
        snap.hl_rows,
        snap.row_count,
        self.scroll_row,
        self.cursor,
        self.color,
        self.gutter_color,
        self.bg_color,
        self.accent_color,
    );

    self.rebuild_cells = false;
}

fn rebuildCells(
    renderer: *Renderer,
    arena_alloc: Allocator,
    rows: []const TextBuffer.Row,
    hl_rows: []const []Buffer.Span,
    row_count: usize,
    scroll_row: u64,
    cursor: CursorPosition,
    default_color: [4]u8,
    gutter_color: [4]u8,
    bg_color: [4]u8,
    accent_color: [4]u8,
) !void {
    renderer.mutex.lock();
    defer renderer.mutex.unlock();

    const grid_size = renderer.size.grid();
    try renderer.ensureCellStoreSize(grid_size);

    renderer.uniforms.bg_color = bg_color;

    renderer.cells.reset();

    renderer.uniforms.cursor_pos = .{
        std.math.maxInt(u16),
        std.math.maxInt(u16),
    };

    const gutter_width = lineNumberGutterWidth(row_count);
    const visible_gutter_width = @min(gutter_width, grid_size.columns);

    var cursor_cell = if (cursor.row >= scroll_row) blk: {
        const row_idx = std.math.cast(usize, cursor.row - scroll_row) orelse break :blk null;
        const col_idx = gutter_width + (std.math.cast(usize, cursor.col) orelse break :blk null);

        if (row_idx >= rows.len or row_idx >= grid_size.rows or col_idx >= grid_size.columns) {
            break :blk null;
        }

        renderer.uniforms.cursor_pos = .{ @intCast(col_idx), @intCast(row_idx) };

        break :blk try renderCellText(renderer, row_idx, col_idx, 0x2588, default_color, .regular);
    } else null;
    if (cursor_cell != null) {
        cursor_cell.?.bools.is_cursor_glyph = true;
    }
    renderer.cells.setCursor(cursor_cell);

    for (rows, 0..) |row_data, row_idx| {
        if (row_idx >= grid_size.rows) break;

        const hl = if (row_idx < hl_rows.len) hl_rows[row_idx] else &[_]Buffer.Span{};
        const line_number = scroll_row + row_idx;

        renderer.cells.bgCell(row_idx, cursor.col + visible_gutter_width).* = accent_color;

        if (line_number == cursor.row) {
            if (cursor.row > scroll_row) {
                for (visible_gutter_width..grid_size.columns) |col| {
                    renderer.cells.bgCell(cursor.row - scroll_row, col).* = accent_color;
                }
            }
        }

        try renderRelativeLineNumber(
            renderer,
            row_idx,
            line_number,
            cursor.row,
            visible_gutter_width,
            default_color,
            gutter_color,
        );

        const shaped = try renderer.grid.shapeRow(arena_alloc, row_data.codepoints);
        for (shaped) |placement| {
            const col_idx = gutter_width + placement.column;
            if (col_idx >= grid_size.columns) continue;

            const span_info = spanAt(hl, placement.column, default_color);
            const cell = try renderShapedGlyph(renderer, row_idx, col_idx, placement, span_info.color, span_info.style) orelse continue;
            try renderer.cells.add(renderer.alloc, .text, cell);
        }
    }

    renderer.cells_rebuilt = true;
}

const SpanResult = struct {
    color: [4]u8,
    style: Style,
};

fn spanAt(spans: []const Buffer.Span, col: usize, default_color: [4]u8) SpanResult {
    for (spans) |span| {
        if (col >= span.start and col < span.end) return .{ .color = span.color, .style = span.style };
        if (col < span.start) break;
    }
    return .{ .color = default_color, .style = .regular };
}

fn renderCellText(renderer: *Renderer, row_idx: usize, col_idx: usize, codepoint: u32, color: [4]u8, style: Style) !?shaderpkg.CellText {
    const glyph = try renderer.grid.renderCodepoint(renderer.alloc, codepoint, style) orelse return null;

    return glyphToCellText(row_idx, col_idx, glyph, 0, 0, color);
}

fn renderShapedGlyph(
    renderer: *Renderer,
    row_idx: usize,
    col_idx: usize,
    placement: fontpkg.Shaper.ShapedGlyph,
    color: [4]u8,
    style: Style,
) !?shaderpkg.CellText {
    const glyph = try renderer.grid.renderGlyph(renderer.alloc, placement.glyph_index, style);

    return glyphToCellText(
        row_idx,
        col_idx,
        glyph,
        placement.x_offset,
        placement.y_offset,
        color,
    );
}

fn renderRelativeLineNumber(
    renderer: *Renderer,
    row_idx: usize,
    line_number: u64,
    cursor_row: u64,
    gutter_width: usize,
    current_line_color: [4]u8,
    gutter_color: [4]u8,
) !void {
    if (gutter_width == 0) return;

    const relative = if (line_number >= cursor_row) line_number - cursor_row else cursor_row - line_number;
    const displayed_number = if (relative == 0) line_number + 1 else relative;
    const separator_cols: usize = if (gutter_width >= 3) 2 else if (gutter_width >= 2) 1 else 0;
    const digit_cols = gutter_width - separator_cols;
    if (digit_cols == 0) return;

    var buf: [32]u8 = undefined;
    const digits = try std.fmt.bufPrint(&buf, "{d}", .{displayed_number});
    const visible_digit_count = @min(digits.len, digit_cols);
    if (visible_digit_count == 0) return;

    const start_col = if (digit_cols > visible_digit_count)
        digit_cols - visible_digit_count
    else
        0;
    const first_digit = digits.len - visible_digit_count;
    const color = if (relative == 0) current_line_color else gutter_color;
    const style: Style = if (relative == 0) .bold else .regular;

    for (digits[first_digit..], 0..) |digit, digit_idx| {
        const cell = try renderCellText(renderer, row_idx, start_col + digit_idx, digit, color, style) orelse continue;
        try renderer.cells.add(renderer.alloc, .text, cell);
    }
}

fn glyphToCellText(
    row_idx: usize,
    col_idx: usize,
    glyph: fontpkg.Glyph,
    x_offset: i16,
    y_offset: i16,
    color: [4]u8,
) !?shaderpkg.CellText {
    if (glyph.width == 0 or glyph.height == 0) return null;

    const bearing_x = clampI16(glyph.offset_x + x_offset);
    const bearing_y = clampI16(glyph.offset_y + y_offset);

    return shaderpkg.CellText{
        .grid_pos = .{ @intCast(col_idx), @intCast(row_idx) },
        .color = color,
        .glyph_pos = .{ glyph.atlas_x, glyph.atlas_y },
        .glyph_size = .{ glyph.width, glyph.height },
        .bearings = .{
            bearing_x,
            bearing_y,
        },
    };
}

pub fn themeUpdate(self: *Editor) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    self.color = self.settings.getColor(.fg);
    self.gutter_color = self.settings.getColor(.gutter);
    self.bg_color = self.settings.getColor(.mutedBg);
    self.accent_color = self.settings.getColor(.accent);

    self.rebuild_cells = true;
}

fn lineNumberGutterWidth(row_count: usize) usize {
    return digitCount(if (row_count > 0) row_count - 1 else 0) + 2;
}

fn digitCount(value: usize) usize {
    var remaining = value;
    var digits: usize = 1;
    while (remaining >= 10) {
        remaining /= 10;
        digits += 1;
    }
    return digits;
}

fn clampI16(v: i32) i16 {
    return std.math.cast(i16, std.math.clamp(v, std.math.minInt(i16), std.math.maxInt(i16))) orelse unreachable;
}
