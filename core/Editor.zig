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

const log = std.log.scoped(.editor);

mutex: std.Thread.Mutex = .{},
project: *Project,
alloc: Allocator,

buffer: ?*Buffer = null,
selected_entry: ?u64 = null,
scroll_row: u64 = 0,

size: sizepkg.ScreenSize,

pub fn init(
    alloc: Allocator,
    project: *Project,
    size: sizepkg.ScreenSize,
) Editor {
    return .{
        .alloc = alloc,
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

        self.emitBufferUpdate(id, buffer);
    }
}

pub fn scroll(self: *Editor, row: u64) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    self.scroll_row = row;
}

pub fn resize(self: *Editor, size: sizepkg.ScreenSize) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    self.size = size;
}

pub fn mouseButton(_: *Editor, event: inputpkg.MouseButtonEvent) void {
    log.debug("mouse button={s} action={s} x={d:.1} y={d:.1} mods=0x{x}", .{
        @tagName(event.button),
        @tagName(event.action),
        event.x,
        event.y,
        @as(u8, @bitCast(event.mods)),
    });
}

pub fn mouseMove(_: *Editor, event: inputpkg.MouseMoveEvent) void {
    log.debug("mouse move x={d:.1} y={d:.1} mods=0x{x}", .{
        event.x,
        event.y,
        @as(u8, @bitCast(event.mods)),
    });
}

pub fn onBufferUpdate(self: *Editor, entry_id: u64) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    const selected_entry = self.selected_entry orelse return;
    if (selected_entry != entry_id) return;

    const buffer = self.buffer orelse return;
    self.emitBufferUpdate(entry_id, buffer);
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
        .entry_id = buffer.entry_id,
        .row_count = text.rowCount,
    };
    return true;
}

fn emitBufferUpdate(_: *Editor, entry_id: u64, buffer: *Buffer) void {
    _ = global.emit(.{ .bufferUpdate = .{
        .entry_id = entry_id,
        .row_count = buffer.text.rowCount,
    } }, .instant);
}

pub fn frameCallback(self: *Editor, renderer: *Renderer) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    const buffer = self.buffer orelse return;
    if (buffer.getState() != .ready) return;

    buffer.mutex.lock();
    defer buffer.mutex.unlock();

    const text = buffer.text;
    const first = text.content.items;
    const second = text.content.secondHalf();

    const grid = renderer.size.grid();
    const rows = grid.rows;
    const cols = grid.columns;

    var new_cells = try std.ArrayList([]u32).initCapacity(self.alloc, 0);
    defer {
        for (new_cells.items) |slice| {
            self.alloc.free(slice);
        }
        new_cells.deinit(self.alloc);
    }

    var line: u64 = 0;
    var row: u16 = 0;
    var remainder: []const u8 = first;
    var in_second = false;

    while (true) {
        if (std.mem.indexOfScalar(u8, remainder, '\n')) |nl| {
            if (line >= self.scroll_row) {
                if (row >= rows) break;
                const line_bytes = remainder[0..nl];
                const codepoints = decodeUtf8Line(self.alloc, line_bytes) catch return;
                new_cells.append(self.alloc, codepoints) catch return;
                row += 1;
            }
            remainder = remainder[nl + 1 ..];
            line += 1;
        } else if (!in_second) {
            in_second = true;
            if (second.len == 0) {
                if (line >= self.scroll_row and row < rows) {
                    const codepoints = decodeUtf8Line(self.alloc, remainder) catch return;
                    new_cells.append(self.alloc, codepoints) catch return;
                }
                break;
            }
            if (std.mem.indexOfScalar(u8, second, '\n')) |nl| {
                if (line >= self.scroll_row) {
                    if (row >= rows) break;
                    const joined = std.mem.concat(self.alloc, u8, &.{ remainder, second[0..nl] }) catch return;
                    defer self.alloc.free(joined);
                    const codepoints = decodeUtf8Line(self.alloc, joined) catch return;
                    new_cells.append(self.alloc, codepoints) catch return;
                    row += 1;
                }
                remainder = second[nl + 1 ..];
                line += 1;
            } else {
                if (line >= self.scroll_row and row < rows) {
                    const joined = std.mem.concat(self.alloc, u8, &.{ remainder, second }) catch return;
                    defer self.alloc.free(joined);
                    const codepoints = decodeUtf8Line(self.alloc, joined) catch return;
                    new_cells.append(self.alloc, codepoints) catch return;
                }
                break;
            }
        } else {
            if (line >= self.scroll_row and row < rows) {
                const codepoints = decodeUtf8Line(self.alloc, remainder) catch return;
                new_cells.append(self.alloc, codepoints) catch return;
            }
            break;
        }
    }

    renderer.rebuildCells(rows, cols, new_cells) catch {};
}

fn decodeUtf8Line(alloc: Allocator, bytes: []const u8) ![]u32 {
    var codepoints = try std.ArrayList(u32).initCapacity(alloc, 0);
    errdefer codepoints.deinit(alloc);

    const view = std.unicode.Utf8View.initUnchecked(bytes);
    var it = view.iterator();
    while (it.nextCodepoint()) |cp| {
        try codepoints.append(alloc, cp);
    }

    return codepoints.toOwnedSlice(alloc);
}
