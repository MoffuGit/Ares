const Editor = @This();

const std = @import("std");
const globalpkg = @import("global.zig");
const global = &globalpkg.state;
const Allocator = std.mem.Allocator;
const Project = @import("Project.zig");
const Buffer = @import("buffer/Buffer.zig");
const SharedState = @import("SharedState.zig");
const Renderer = @import("Renderer.zig");

const log = std.log.scoped(.editor);

project: *Project,
alloc: Allocator,
shared_state: *SharedState,
renderer: *Renderer,

buffer: ?*Buffer = null,
selected_entry: ?u64 = null,
scroll_row: u64 = 0,

pub fn init(
    alloc: Allocator,
    project: *Project,
) Editor {
    return .{
        .alloc = alloc,
        .project = project,
        .shared_state = undefined,
        .renderer = undefined,
    };
}

pub fn deinit(self: *Editor) void {
    _ = self;
}

pub fn selectEntry(self: *Editor, id: u64) void {
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
    self.scroll_row = row;
}

pub fn onBufferUpdate(self: *Editor, entry_id: u64) void {
    const selected_entry = self.selected_entry orelse return;
    if (selected_entry != entry_id) return;

    const buffer = self.buffer orelse return;
    self.emitBufferUpdate(entry_id, buffer);
}

pub fn onThemeUpdate(self: *Editor) void {
    self.syncTextColor();
}

pub fn syncTextColor(self: *Editor) void {
    const color = self.project.app.settings.readThemeTextColor();
    self.renderer.setTextColor(color);
}

pub fn readEditorState(self: *Editor, out: *globalpkg.ExternEditorState) bool {
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

pub fn writeScreen(self: *Editor) void {
    const buffer = self.buffer orelse return;

    if (buffer.getState() == .ready) {
        buffer.mutex.lock();
        defer buffer.mutex.unlock();

        const text = buffer.text;

        const first = text.content.items;
        const second = text.content.secondHalf();

        self.shared_state.mutex.lock();
        defer self.shared_state.mutex.unlock();

        const screen = &self.shared_state.screen;

        screen.resetCells();

        var line: u64 = 0;
        var row: u16 = 0;
        var remainder: []const u8 = first;
        var in_second = false;

        while (true) {
            if (std.mem.indexOfScalar(u8, remainder, '\n')) |nl| {
                if (line >= self.scroll_row) {
                    if (row >= screen.rows) break;
                    screen.addNewLine(remainder[0..nl]) catch |err| {
                        log.err("failed to add line to screen: {}", .{err});
                        return;
                    };
                    row += 1;
                }
                remainder = remainder[nl + 1 ..];
                line += 1;
            } else if (!in_second) {
                in_second = true;
                if (second.len == 0) {
                    if (line >= self.scroll_row and row < screen.rows) {
                        screen.addNewLine(remainder) catch |err| {
                            log.err("failed to add line to screen: {}", .{err});
                            return;
                        };
                    }
                    break;
                }
                if (std.mem.indexOfScalar(u8, second, '\n')) |nl| {
                    if (line >= self.scroll_row) {
                        if (row >= screen.rows) break;
                        const joined = std.mem.concat(self.alloc, u8, &.{ remainder, second[0..nl] }) catch return;
                        defer self.alloc.free(joined);
                        screen.addNewLine(joined) catch |err| {
                            log.err("failed to add line to screen: {}", .{err});
                            return;
                        };
                        row += 1;
                    }
                    remainder = second[nl + 1 ..];
                    line += 1;
                } else {
                    if (line >= self.scroll_row and row < screen.rows) {
                        const joined = std.mem.concat(self.alloc, u8, &.{ remainder, second }) catch return;
                        defer self.alloc.free(joined);
                        screen.addNewLine(joined) catch |err| {
                            log.err("failed to add line to screen: {}", .{err});
                            return;
                        };
                    }
                    break;
                }
            } else {
                if (line >= self.scroll_row and row < screen.rows) {
                    screen.addNewLine(remainder) catch |err| {
                        log.err("failed to add line to screen: {}", .{err});
                        return;
                    };
                }
                break;
            }
        }
    }
}

fn emitBufferUpdate(_: *Editor, entry_id: u64, buffer: *Buffer) void {
    _ = global.emit(.{ .bufferUpdate = .{
        .entry_id = entry_id,
        .row_count = buffer.text.rowCount,
    } }, .instant);
}
