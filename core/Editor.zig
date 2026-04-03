const Editor = @This();

const std = @import("std");
const global = &@import("global.zig").state;
const Allocator = std.mem.Allocator;
const SharedState = @import("SharedState.zig");
const sizepkg = @import("size.zig");
const Project = @import("Project.zig");
const Buffer = @import("buffer/Buffer.zig");
const EditorThread = @import("editor/Thread.zig");
const Surface = @import("Surface.zig");
const App = @import("App.zig");

const log = std.log.scoped(.editor);

alloc: Allocator,
project: *Project,
surface: *Surface,

buffer: ?*Buffer = null,
selected_entry: ?u64 = null,
scroll_row: u64 = 0,

thread: EditorThread,
thr: std.Thread,

pub fn create(app: *App, project: *Project, alloc: Allocator, layer_ptr: *anyopaque) !*Editor {
    const self = try alloc.create(Editor);
    errdefer alloc.destroy(self);

    const surface = try Surface.create(alloc, &app.grid, layer_ptr);
    errdefer surface.destroy();

    var editor_thread = try EditorThread.init(alloc, self);
    errdefer editor_thread.deinit();

    self.* = .{
        .thread = editor_thread,
        .alloc = alloc,
        .project = project,
        .surface = surface,
        .thr = undefined,
    };

    self.syncTextColor();

    try global.events.on(.bufferUpdate, .{ .ctx = self, .handle = onBufferUpdate });
    errdefer global.events.off(.bufferUpdate, .{ .ctx = self, .handle = onBufferUpdate });

    try global.events.on(.themeUpdate, .{ .ctx = self, .handle = onThemeUpdate });
    errdefer global.events.off(.themeUpdate, .{ .ctx = self, .handle = onThemeUpdate });

    self.thr = try std.Thread.spawn(.{}, EditorThread.threadMain, .{&self.thread});

    return self;
}
pub fn destroy(self: *Editor) void {
    {
        self.thread.stop.notify() catch |err|
            log.err("error notifying editor thread to stop, may stall err={}", .{err});
        self.thr.join();
    }

    self.surface.destroy();

    global.events.off(.bufferUpdate, .{ .ctx = self, .handle = onBufferUpdate });
    global.events.off(.themeUpdate, .{ .ctx = self, .handle = onThemeUpdate });

    self.thread.deinit();
    self.alloc.destroy(self);
}

fn onBufferUpdate(ctx: *anyopaque, event: @import("global.zig").GlobalEvents) void {
    const self: *Editor = @ptrCast(@alignCast(ctx));

    const entry_id = self.selected_entry orelse return;
    if (event.bufferUpdate != entry_id) return;

    if (self.buffer) |buffer| {
        const cell = self.surface.grid.cellSize();
        _ = global.emit(.{ .bufferUpdate = .{
            .entry_id = entry_id,
            .row_count = buffer.text.rowCount,
            .cell_width = cell.width,
            .cell_height = cell.height,
            .renderer_health = @intCast(@intFromEnum(self.surface.renderer.health.load(.seq_cst))),
        } }, .instant);
    }

    _ = self.thread.mailbox.push(.{ .buffer_update = {} }, .instant);
    self.thread.wakeup.notify() catch {};
}

fn onThemeUpdate(ctx: *anyopaque, _: @import("global.zig").GlobalEvents) void {
    const self: *Editor = @ptrCast(@alignCast(ctx));
    self.syncTextColor();
}

fn syncTextColor(self: *Editor) void {
    const color = self.project.app.settings.readThemeTextColor();
    self.surface.renderer.setTextColor(color);
}

pub fn resize(self: *Editor, size: sizepkg.ScreenSize) void {
    {
        self.surface.shared_state.mutex.lock();
        defer self.surface.shared_state.mutex.unlock();

        self.surface.shared_state.screen.resize(.{ .screen = size, .cell = self.surface.grid.cellSize() });
    }

    self.writeScreen();

    self.surface.resize(size);
}

pub fn selectSurfaceEntry(self: *Editor, id: u64) void {
    if (self.buffer) |curr| {
        if (curr.entry_id == id) return;
    }

    if (self.project.buffer_store.open(id)) |buffer| {
        self.buffer = buffer;
        self.selected_entry = id;

        const cell = self.surface.grid.cellSize();
        _ = global.emit(.{ .bufferUpdate = .{
            .entry_id = id,
            .row_count = buffer.text.rowCount,
            .cell_width = cell.width,
            .cell_height = cell.height,
            .renderer_health = @intCast(@intFromEnum(self.surface.renderer.health.load(.seq_cst))),
        } }, .instant);

        self.writeScreen();

        self.surface.wakeup();
    }
}

pub fn scroll(self: *Editor, row: u64) void {
    self.scroll_row = row;
    self.writeScreen();
}

pub fn writeScreen(self: *Editor) void {
    const buffer = self.buffer orelse return;

    if (buffer.getState() == .ready) {
        buffer.mutex.lock();
        defer buffer.mutex.unlock();

        const text = buffer.text;

        const first = text.content.items;
        const second = text.content.secondHalf();

        self.surface.shared_state.mutex.lock();
        defer self.surface.shared_state.mutex.unlock();

        const screen = &self.surface.shared_state.screen;

        screen.resetCells();

        var line: u64 = 0;
        var row: u16 = 0;
        var remainder: []const u8 = first;
        var in_second = false;

        while (true) {
            if (std.mem.indexOfScalar(u8, remainder, '\n')) |nl| {
                if (line >= self.scroll_row) {
                    if (row >= screen.rows) break;
                    screen.addNewLine(remainder[0..nl]) catch |e| {
                        log.err("failed to add line to screen: {}", .{e});
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
                        screen.addNewLine(remainder) catch |e| {
                            log.err("failed to add line to screen: {}", .{e});
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
                        screen.addNewLine(joined) catch |e| {
                            log.err("failed to add line to screen: {}", .{e});
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
                        screen.addNewLine(joined) catch |e| {
                            log.err("failed to add line to screen: {}", .{e});
                            return;
                        };
                    }
                    break;
                }
            } else {
                if (line >= self.scroll_row and row < screen.rows) {
                    screen.addNewLine(remainder) catch |e| {
                        log.err("failed to add line to screen: {}", .{e});
                        return;
                    };
                }
                break;
            }
        }
    }

    self.surface.wakeup();
}

pub fn setVisibility(self: *Editor, visible: bool) !void {
    try self.surface.setVisibility(visible);
}
