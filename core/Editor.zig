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

const log = std.log.scoped(.editor);

alloc: Allocator,
project: *Project,
surface: *Surface,

buffer: ?*Buffer = null,
selected_entry: ?u64 = null,
scroll_row: u64 = 0,

editor_thread: EditorThread,
editor_thr: std.Thread,

pub fn create(project: *Project, alloc: Allocator, layer_ptr: *anyopaque) !*Editor {
    const self = try alloc.create(Editor);
    errdefer alloc.destroy(self);

    const surface = try Surface.create(alloc, layer_ptr);
    errdefer surface.destroy();

    try global.events.on(.bufferUpdate, .{ .ctx = self, .handle = onBufferUpdate });
    errdefer global.events.off(.bufferUpdate, .{ .ctx = self, .handle = onBufferUpdate });

    var editor_thread = try EditorThread.init(alloc, self);
    errdefer editor_thread.deinit();

    self.* = .{
        .editor_thread = editor_thread,
        .alloc = alloc,
        .project = project,
        .surface = surface,
        .editor_thr = undefined,
    };

    self.editor_thr = try std.Thread.spawn(.{}, EditorThread.threadMain, .{&self.editor_thread});

    return self;
}
pub fn destroy(self: *Editor) void {
    {
        self.editor_thread.stop.notify() catch |err|
            log.err("error notifying editor thread to stop, may stall err={}", .{err});
        self.editor_thr.join();
    }

    self.surface.destroy();

    global.events.off(.bufferUpdate, .{ .ctx = self, .handle = onBufferUpdate });

    self.editor_thread.deinit();
    self.alloc.destroy(self);
}

fn onBufferUpdate(ctx: *anyopaque, event: @import("global.zig").GlobalEvents) void {
    const self: *Editor = @ptrCast(@alignCast(ctx));

    const entry_id = self.selected_entry orelse return;
    if (event.bufferUpdate != entry_id) return;

    const thread = self.editor_thread;
    _ = thread.mailbox.push(.{ .buffer_update = {} }, .instant);
    thread.wakeup.notify() catch {};
}

pub fn resize(self: *Editor, size: sizepkg.ScreenSize) void {
    {
        var shared_state = self.surface.shared_state;
        shared_state.mutex.lock();
        defer shared_state.mutex.unlock();

        shared_state.screen.resize(.{ .screen = size, .cell = self.surface.grid.cellSize() });
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

        const doc = buffer.document orelse return;
        const first = doc.content.items;
        const second = doc.content.secondHalf();

        var shared_state = self.surface.shared_state;
        shared_state.mutex.lock();
        defer shared_state.mutex.unlock();

        shared_state.screen.resetCells();

        var line: u64 = 0;
        var row: u16 = 0;
        var remainder: []const u8 = first;
        var in_second = false;

        while (true) {
            if (std.mem.indexOfScalar(u8, remainder, '\n')) |nl| {
                if (line >= self.scroll_row) {
                    if (row >= shared_state.screen.rows) break;
                    shared_state.screen.addNewLine(remainder[0..nl]) catch |e| {
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
                    if (line >= self.scroll_row and row < shared_state.screen.rows) {
                        shared_state.screen.addNewLine(remainder) catch |e| {
                            log.err("failed to add line to screen: {}", .{e});
                            return;
                        };
                    }
                    break;
                }
                if (std.mem.indexOfScalar(u8, second, '\n')) |nl| {
                    if (line >= self.scroll_row) {
                        if (row >= shared_state.screen.rows) break;
                        const joined = std.mem.concat(self.alloc, u8, &.{ remainder, second[0..nl] }) catch return;
                        defer self.alloc.free(joined);
                        shared_state.screen.addNewLine(joined) catch |e| {
                            log.err("failed to add line to screen: {}", .{e});
                            return;
                        };
                        row += 1;
                    }
                    remainder = second[nl + 1 ..];
                    line += 1;
                } else {
                    if (line >= self.scroll_row and row < shared_state.screen.rows) {
                        const joined = std.mem.concat(self.alloc, u8, &.{ remainder, second }) catch return;
                        defer self.alloc.free(joined);
                        shared_state.screen.addNewLine(joined) catch |e| {
                            log.err("failed to add line to screen: {}", .{e});
                            return;
                        };
                    }
                    break;
                }
            } else {
                if (line >= self.scroll_row and row < shared_state.screen.rows) {
                    shared_state.screen.addNewLine(remainder) catch |e| {
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
