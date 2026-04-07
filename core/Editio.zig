const Editio = @This();

const std = @import("std");
const globalpkg = @import("global.zig");
const global = &globalpkg.state;
const Allocator = std.mem.Allocator;
const SharedState = @import("SharedState.zig");
const sizepkg = @import("size.zig");
const Project = @import("Project.zig");
const Buffer = @import("buffer/Buffer.zig");
const Renderer = @import("Renderer.zig");
const RendererThread = @import("renderer/Thread.zig");
const Grid = @import("font/mod.zig").Grid;

pub const Thread = @import("editio/Thread.zig").Thread;

const log = std.log.scoped(.editio);

pub const InitConfig = struct {
    project: *Project,
};

alloc: Allocator,
project: *Project,
grid: *Grid,
shared_state: *SharedState,
renderer: *Renderer,
renderer_thread: *RendererThread,
io_thread: ?*Thread = null,

buffer: ?*Buffer = null,
selected_entry: ?u64 = null,
scroll_row: u64 = 0,

pub fn init(
    alloc: Allocator,
    grid: *Grid,
    shared_state: *SharedState,
    renderer: *Renderer,
    renderer_thread: *RendererThread,
    _: sizepkg.ScreenSize,
    config: InitConfig,
) !Editio {
    return .{
        .alloc = alloc,
        .project = config.project,
        .grid = grid,
        .shared_state = shared_state,
        .renderer = renderer,
        .renderer_thread = renderer_thread,
    };
}

pub fn deinit(self: *Editio) void {
    _ = self;
}

pub fn threadEnter(self: *Editio, io_thread: *Thread) !void {
    self.io_thread = io_thread;

    self.syncTextColor();

    try global.events.on(.bufferUpdate, .{ .ctx = self, .handle = handleBufferUpdateEvent });
    errdefer global.events.off(.bufferUpdate, .{ .ctx = self, .handle = handleBufferUpdateEvent });

    try global.events.on(.themeUpdate, .{ .ctx = self, .handle = handleThemeUpdateEvent });
    errdefer global.events.off(.themeUpdate, .{ .ctx = self, .handle = handleThemeUpdateEvent });
}

pub fn threadExit(self: *Editio) void {
    self.io_thread = null;
    global.events.off(.bufferUpdate, .{ .ctx = self, .handle = handleBufferUpdateEvent });
    global.events.off(.themeUpdate, .{ .ctx = self, .handle = handleThemeUpdateEvent });
}

pub fn resize(self: *Editio, size: sizepkg.ScreenSize) void {
    _ = size;
    self.writeScreen();
}

pub fn selectEntry(self: *Editio, id: u64) void {
    if (self.buffer) |curr| {
        if (curr.entry_id == id) return;
    }

    if (self.project.openBuffer(id)) |buffer| {
        self.buffer = buffer;
        self.selected_entry = id;

        self.emitBufferUpdate(id, buffer);
        self.writeScreen();
    }
}

pub fn scroll(self: *Editio, row: u64) void {
    self.scroll_row = row;
    self.writeScreen();
}

pub fn onBufferUpdate(self: *Editio, entry_id: u64) void {
    const selected_entry = self.selected_entry orelse return;
    if (selected_entry != entry_id) return;

    const buffer = self.buffer orelse return;
    self.emitBufferUpdate(entry_id, buffer);
    self.writeScreen();
}

pub fn onThemeUpdate(self: *Editio) void {
    self.syncTextColor();
}

pub fn syncTextColor(self: *Editio) void {
    const color = self.project.app.settings.readThemeTextColor();
    self.renderer.setTextColor(color);
}

pub fn readEditorState(self: *Editio, out: *globalpkg.ExternEditorState) bool {
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

pub fn writeScreen(self: *Editio) void {
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

    self.renderer_thread.wakeup.notify() catch {};
}

fn emitBufferUpdate(_: *Editio, entry_id: u64, buffer: *Buffer) void {
    _ = global.emit(.{ .bufferUpdate = .{
        .entry_id = entry_id,
        .row_count = buffer.text.rowCount,
    } }, .instant);
}

fn handleBufferUpdateEvent(ctx: *anyopaque, event: globalpkg.GlobalEvents) void {
    const self: *Editio = @ptrCast(@alignCast(ctx));
    const io_thread = self.io_thread orelse return;

    _ = io_thread.mailbox.push(.{ .buffer_update = event.bufferUpdate }, .instant);
    io_thread.wakeup.notify() catch {};
}

fn handleThemeUpdateEvent(ctx: *anyopaque, _: globalpkg.GlobalEvents) void {
    const self: *Editio = @ptrCast(@alignCast(ctx));
    const io_thread = self.io_thread orelse return;

    _ = io_thread.mailbox.push(.{ .theme_update = {} }, .instant);
    io_thread.wakeup.notify() catch {};
}
