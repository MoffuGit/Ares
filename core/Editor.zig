const Editor = @This();

const std = @import("std");
const global = &@import("global.zig").state;
const Allocator = std.mem.Allocator;
const SharedState = @import("SharedState.zig");
const sizepkg = @import("size.zig");
const Project = @import("Project.zig");
const Buffer = @import("buffer/Buffer.zig");
const RendererThread = @import("renderer/Thread.zig");
const EditorThread = @import("editor/Thread.zig");

const log = std.log.scoped(.screen);

alloc: Allocator,
shared_state: *SharedState,
project: *Project,
buffer: ?*Buffer = null,
selected_entry: ?u64 = null,
scroll_row: u64 = 0,
renderer_thread: *RendererThread,
editor_thread: ?*EditorThread = null,

pub fn create(project: *Project, alloc: Allocator, renderer_thread: *RendererThread, shared_state: *SharedState) !*Editor {
    const self = try alloc.create(Editor);
    self.* = .{
        .renderer_thread = renderer_thread,
        .alloc = alloc,
        .shared_state = shared_state,
        .project = project,
    };

    try global.events.on(.bufferUpdate, .{ .ctx = self, .handle = onBufferUpdate });

    return self;
}

pub fn destroy(self: *Editor) void {
    global.events.off(.bufferUpdate, .{ .ctx = self, .handle = onBufferUpdate });

    self.alloc.destroy(self);
}

fn onBufferUpdate(ctx: *anyopaque, event: @import("global.zig").GlobalEvents) void {
    const self: *Editor = @ptrCast(@alignCast(ctx));

    const entry_id = self.selected_entry orelse return;
    if (event.bufferUpdate != entry_id) return;

    const thread = self.editor_thread orelse return;
    _ = thread.mailbox.push(.{ .buffer_update = {} }, .instant);
    thread.wakeup.notify() catch {};
}

pub fn resize(self: *Editor, size: sizepkg.Size) void {
    {
        self.shared_state.mutex.lock();
        defer self.shared_state.mutex.unlock();

        self.shared_state.screen.resize(size);
    }

    self.writeScreen();

    _ = self.renderer_thread.mailbox.push(.{ .resize = .{
        .height = size.screen.height,
        .width = size.screen.width,
    } }, .instant);
    self.renderer_thread.wakeup.notify() catch {};
}

pub fn selectSurfaceEntry(self: *Editor, id: u64) void {
    log.debug("selected entry: {}", .{id});
    if (self.buffer) |curr| {
        if (curr.entry_id == id) return;
    }

    if (self.project.buffer_store.open(id)) |buffer| {
        self.buffer = buffer;
        self.selected_entry = id;
        self.writeScreen();

        self.renderer_thread.wakeup.notify() catch {};
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

        self.shared_state.mutex.lock();
        defer self.shared_state.mutex.unlock();

        self.shared_state.screen.resetCells();

        var line: u64 = 0;
        var row: u16 = 0;
        var remainder: []const u8 = first;
        var in_second = false;

        while (true) {
            if (std.mem.indexOfScalar(u8, remainder, '\n')) |nl| {
                if (line >= self.scroll_row) {
                    if (row >= self.shared_state.screen.rows) break;
                    self.shared_state.screen.addNewLine(remainder[0..nl]) catch |e| {
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
                    if (line >= self.scroll_row and row < self.shared_state.screen.rows) {
                        self.shared_state.screen.addNewLine(remainder) catch |e| {
                            log.err("failed to add line to screen: {}", .{e});
                            return;
                        };
                    }
                    break;
                }
                if (std.mem.indexOfScalar(u8, second, '\n')) |nl| {
                    if (line >= self.scroll_row) {
                        if (row >= self.shared_state.screen.rows) break;
                        const joined = std.mem.concat(self.alloc, u8, &.{ remainder, second[0..nl] }) catch return;
                        defer self.alloc.free(joined);
                        self.shared_state.screen.addNewLine(joined) catch |e| {
                            log.err("failed to add line to screen: {}", .{e});
                            return;
                        };
                        row += 1;
                    }
                    remainder = second[nl + 1 ..];
                    line += 1;
                } else {
                    if (line >= self.scroll_row and row < self.shared_state.screen.rows) {
                        const joined = std.mem.concat(self.alloc, u8, &.{ remainder, second }) catch return;
                        defer self.alloc.free(joined);
                        self.shared_state.screen.addNewLine(joined) catch |e| {
                            log.err("failed to add line to screen: {}", .{e});
                            return;
                        };
                    }
                    break;
                }
            } else {
                if (line >= self.scroll_row and row < self.shared_state.screen.rows) {
                    self.shared_state.screen.addNewLine(remainder) catch |e| {
                        log.err("failed to add line to screen: {}", .{e});
                        return;
                    };
                }
                break;
            }
        }
    }

    self.renderer_thread.wakeup.notify() catch {};
}
