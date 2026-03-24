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

fn onBufferUpdate(ctx: *anyopaque) void {
    const self: *Editor = @ptrCast(@alignCast(ctx));

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
}

pub fn selectEntry(self: *Editor, id: u64) void {
    log.debug("selected entry: {}", .{id});
    if (self.buffer) |curr| {
        if (curr.entry_id == id) return;
    }

    if (self.project.buffer_store.open(id)) |buffer| {
        self.buffer = buffer;
        self.writeScreen();

        self.renderer_thread.wakeup.notify() catch {};
    }
}

pub fn writeScreen(self: *Editor) void {
    const buffer = self.buffer orelse return;

    if (buffer.getState() == .ready) {
        const content = buffer.bytes() orelse return;

        self.shared_state.mutex.lock();
        defer self.shared_state.mutex.unlock();

        self.shared_state.screen.resetCells();

        var line_it = std.mem.splitScalar(u8, content, '\n');
        var row: u16 = 0;
        while (line_it.next()) |line| {
            if (row >= self.shared_state.screen.rows) break;
            self.shared_state.screen.addNewLine(line) catch |e| {
                log.err("failed to add line to screen: {}", .{e});
                return;
            };
            row += 1;
        }
    }

    self.renderer_thread.wakeup.notify() catch {};
}
