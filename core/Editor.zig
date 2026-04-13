const Editor = @This();

const std = @import("std");
const globalpkg = @import("global.zig");
const global = &globalpkg.state;
const Allocator = std.mem.Allocator;
const inputpkg = @import("input.zig");
const Project = @import("Project.zig");
const Buffer = @import("buffer/Buffer.zig");
const Renderer = @import("Renderer.zig");
const sizepkg = @import("size.zig");
const shaderpkg = Renderer.GraphicsAPI.shaders;

const log = std.log.scoped(.editor);

pub const CursorPosition = struct {
    row: u64 = 0,
    col: u64 = 0,
};

mutex: std.Thread.Mutex = .{},
project: *Project,
alloc: Allocator,
surface_id: u64,

buffer: ?*Buffer = null,
selected_entry: ?u64 = null,
scroll_row: u64 = 0,
cursor: CursorPosition = .{},
rebuild_cells: bool = false,

size: sizepkg.ScreenSize,

pub fn init(
    alloc: Allocator,
    surface_id: u64,
    project: *Project,
    size: sizepkg.ScreenSize,
) Editor {
    return .{
        .alloc = alloc,
        .surface_id = surface_id,
        .project = project,
        .size = size,
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

pub fn resize(self: *Editor, size: sizepkg.ScreenSize) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    self.size = size;
    self.rebuild_cells = true;
}

pub fn mouseButton(_: *Editor, _: inputpkg.MouseButtonEvent) void {}

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
        .surface_id = self.surface_id,
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
        .surface_id = self.surface_id,
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

    try rebuildCells(renderer, text.visibleRows(self.scroll_row, grid.rows));

    self.rebuild_cells = false;
}

fn rebuildCells(renderer: *Renderer, rows: []const Buffer.TextBuffer.Row) !void {
    renderer.mutex.lock();
    defer renderer.mutex.unlock();

    const grid_size = renderer.size.grid();
    try renderer.ensureCellStoreSize(grid_size);

    renderer.cells.reset();

    for (rows, 0..) |row_data, row_idx| {
        if (row_idx >= grid_size.rows) break;

        for (row_data.codepoints, 0..) |cell_codepoint, col_idx| {
            if (col_idx >= grid_size.columns) break;

            const glyph = try renderer.grid.renderCodepoint(renderer.alloc, cell_codepoint) orelse continue;

            try renderer.cells.add(renderer.alloc, .text, shaderpkg.CellText{
                .grid_pos = .{ @intCast(col_idx), @intCast(row_idx) },
                .color = renderer.text_color,
                .glyph_pos = .{ glyph.atlas_x, glyph.atlas_y },
                .glyph_size = .{ glyph.width, glyph.height },
                .bearings = .{
                    @intCast(glyph.offset_x),
                    @intCast(glyph.offset_y),
                },
            });
        }
    }

    renderer.cells_rebuilt = true;
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
