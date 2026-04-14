const Editor = @This();

const std = @import("std");
const globalpkg = @import("global.zig");
const global = &globalpkg.state;
const Allocator = std.mem.Allocator;
const inputpkg = @import("input.zig");
const Project = @import("Project.zig");
const Buffer = @import("buffer/Buffer.zig");
const Renderer = @import("Renderer.zig");
const fontpkg = @import("font/mod.zig");
const sizepkg = @import("size.zig");
const shaderpkg = Renderer.GraphicsAPI.shaders;
const Settings = @import("settings/mod.zig");

const log = std.log.scoped(.editor);

pub const CursorPosition = struct {
    row: u64 = 0,
    col: u64 = 0,
};

mutex: std.Thread.Mutex = .{},
project: *Project,
alloc: Allocator,
settings: *Settings,
id: u64,

buffer: ?*Buffer = null,
selected_entry: ?u64 = null,
scroll_row: u64 = 0,
cursor: CursorPosition = .{},
rebuild_cells: bool = false,
color: [4]u8,

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
        .color = settings.readThemeTextColor(),
    };
}

pub fn deinit(self: *Editor) void {
    _ = self;
}

pub fn selectEntry(self: *Editor, id: u64) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    if (self.buffer) |curr| {
        if (curr.entry_id == id) return;
    }

    if (self.project.openBuffer(id)) |buffer| {
        self.buffer = buffer;
        self.selected_entry = id;
        self.cursor = .{};
        self.rebuild_cells = true;

        self.emitEditorUpdate(id, buffer);
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

    const buffer = self.buffer orelse return;
    self.clampCursorToBuffer(buffer);
    self.emitEditorUpdate(buffer.entry_id, buffer);
    self.rebuild_cells = true;
}

pub fn resize(self: *Editor, size: sizepkg.Size) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    self.size = size;
    self.rebuild_cells = true;
}

pub fn mouseButton(self: *Editor, evt: inputpkg.MouseButtonEvent) void {
    if (evt.button != .left or evt.action != .release) return;

    self.mutex.lock();
    defer self.mutex.unlock();

    const buffer = self.buffer orelse return;

    const cell_width: f64 = @floatFromInt(self.size.cell.width);
    const cell_height: f64 = @floatFromInt(self.size.cell.height);

    const col: u64 = if (evt.x >= 0) @intFromFloat(evt.x / cell_width) else 0;
    const row: u64 = if (evt.y >= 0) @intFromFloat(evt.y / cell_height) else 0;

    self.cursor = .{ .row = self.scroll_row + row, .col = col };
    // self.clampCursorToBuffer(buffer);
    self.emitEditorUpdate(buffer.entry_id, buffer);
    self.rebuild_cells = true;
}

pub fn mouseMove(_: *Editor, _: inputpkg.MouseMoveEvent) void {}

pub fn onBufferUpdate(self: *Editor, entry_id: u64) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    const buffer = self.buffer orelse return;
    if (buffer.entry_id != entry_id) return;
    self.clampCursorToBuffer(buffer);
    self.emitEditorUpdate(entry_id, buffer);
    self.rebuild_cells = true;
}

pub fn readEditorState(self: *Editor, out: *globalpkg.ExternEditorState) bool {
    self.mutex.lock();
    defer self.mutex.unlock();

    const buffer = self.buffer orelse return false;
    if (buffer.getState() != .ready) return false;

    buffer.mutex.lock();
    defer buffer.mutex.unlock();

    const text = buffer.text;
    out.* = .{
        .surface_id = self.id,
        .entry_id = buffer.entry_id,
        .row_count = text.rowCount,
        .cursor_row = self.cursor.row,
        .cursor_col = self.cursor.col,
    };
    return true;
}

fn emitEditorUpdate(self: *Editor, entry_id: u64, buffer: *Buffer) void {
    buffer.mutex.lock();
    defer buffer.mutex.unlock();

    _ = global.emit(.{ .editorUpdate = .{
        .surface_id = self.id,
        .entry_id = entry_id,
        .row_count = buffer.text.rowCount,
        .cursor_row = self.cursor.row,
        .cursor_col = self.cursor.col,
    } }, .instant);
}

fn clampCursorToBuffer(self: *Editor, buffer: *Buffer) void {
    if (buffer.getState() != .ready) return;

    buffer.mutex.lock();
    defer buffer.mutex.unlock();

    const text = &buffer.text;
    if (text.rowCount == 0) {
        self.cursor = .{};
        return;
    }

    const max_row = text.rowCount - 1;
    const cursor_row = @min(std.math.cast(usize, self.cursor.row) orelse max_row, max_row);
    const rows = text.visibleRows(cursor_row, 1);
    const max_col = if (rows.len == 0) 0 else rows[0].codepoints.len;

    self.cursor = .{
        .row = cursor_row,
        .col = @min(std.math.cast(usize, self.cursor.col) orelse max_col, max_col),
    };
}

pub fn frameCallback(self: *Editor, renderer: *Renderer) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    const buffer = self.buffer orelse return;
    if (buffer.getState() != .ready) return;

    buffer.mutex.lock();
    defer buffer.mutex.unlock();

    const grid = renderer.size.grid();
    const text = &buffer.text;

    if (!self.rebuild_cells) return;

    try rebuildCells(renderer, text.visibleRows(self.scroll_row, grid.rows), self.scroll_row, self.cursor, self.color);

    self.rebuild_cells = false;
}

fn rebuildCells(
    renderer: *Renderer,
    rows: []const Buffer.TextBuffer.Row,
    scroll_row: u64,
    cursor: CursorPosition,
    color: [4]u8,
) !void {
    renderer.mutex.lock();
    defer renderer.mutex.unlock();

    var arena = std.heap.ArenaAllocator.init(renderer.alloc);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const grid_size = renderer.size.grid();
    try renderer.ensureCellStoreSize(grid_size);

    renderer.cells.reset();

    renderer.uniforms.cursor_pos = .{
        std.math.maxInt(u16),
        std.math.maxInt(u16),
    };

    var cursor_cell = if (cursor.row >= scroll_row) blk: {
        const row_idx = std.math.cast(usize, cursor.row - scroll_row) orelse break :blk null;
        const col_idx = std.math.cast(usize, cursor.col) orelse break :blk null;

        if (row_idx >= rows.len or row_idx >= grid_size.rows or col_idx >= grid_size.columns) {
            break :blk null;
        }

        renderer.uniforms.cursor_pos = .{ @intCast(col_idx), @intCast(row_idx) };

        break :blk try renderCellText(renderer, row_idx, col_idx, 0x2588, color);
    } else null;
    if (cursor_cell != null) {
        cursor_cell.?.bools.is_cursor_glyph = true;
    }
    renderer.cells.setCursor(cursor_cell);

    for (rows, 0..) |row_data, row_idx| {
        if (row_idx >= grid_size.rows) break;

        const shaped = try renderer.grid.shapeRow(arena_alloc, row_data.codepoints);
        for (shaped) |placement| {
            if (placement.column >= grid_size.columns) continue;

            const cell = try renderShapedGlyph(renderer, row_idx, placement, color) orelse continue;
            try renderer.cells.add(renderer.alloc, .text, cell);
        }
    }

    renderer.cells_rebuilt = true;
}

fn renderCellText(renderer: *Renderer, row_idx: usize, col_idx: usize, codepoint: u32, color: [4]u8) !?shaderpkg.CellText {
    const glyph = try renderer.grid.renderCodepoint(renderer.alloc, codepoint) orelse return null;

    return glyphToCellText(row_idx, col_idx, glyph, 0, 0, color);
}

fn renderShapedGlyph(
    renderer: *Renderer,
    row_idx: usize,
    placement: fontpkg.Shaper.ShapedGlyph,
    color: [4]u8,
) !?shaderpkg.CellText {
    const glyph = try renderer.grid.renderGlyph(renderer.alloc, placement.glyph_index);

    return glyphToCellText(
        row_idx,
        placement.column,
        glyph,
        placement.x_offset,
        placement.y_offset,
        color,
    );
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

    self.color = self.settings.readThemeTextColor();

    self.rebuild_cells = true;
}

fn clampI16(v: i32) i16 {
    return std.math.cast(i16, std.math.clamp(v, std.math.minInt(i16), std.math.maxInt(i16))) orelse unreachable;
}

test "setCursorPosition clamps to the selected buffer layout" {
    try global.init(null);
    defer global.deinit();

    var buffer = Buffer.init(std.testing.allocator, 42);
    defer buffer.deinit();

    buffer.text.deinit();
    buffer.text = try Buffer.TextBuffer.initFromBytes(std.testing.allocator, "abc\nxy");
    buffer.state.store(.ready, .release);

    var editor = Editor.init(std.testing.allocator, 7, undefined, .{ .width = 80, .height = 40 });
    editor.buffer = &buffer;
    editor.selected_entry = buffer.entry_id;

    editor.setCursorPosition(99, 99);

    var out: globalpkg.ExternEditorState = undefined;
    try std.testing.expect(editor.readEditorState(&out));
    try std.testing.expectEqual(@as(u64, 1), out.cursor_row);
    try std.testing.expectEqual(@as(u64, 2), out.cursor_col);
}
