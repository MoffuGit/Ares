const Editor = @This();

const std = @import("std");
const global = &@import("../global.zig").state;
const Allocator = std.mem.Allocator;
const SharedState = @import("../SharedState.zig");
const sizepkg = @import("../size.zig");
const Project = @import("../Project.zig");
const Buffer = @import("../buffer/Buffer.zig");

const log = std.log.scoped(.screen);

alloc: Allocator,
shared_state: *SharedState,
project: *Project,
buffer: ?*Buffer = null,

pub fn create(project: *Project, alloc: Allocator, shared_state: *SharedState) !*Editor {
    const self = try alloc.create(Editor);
    self.* = .{
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

pub fn onBufferUpdate(ctx: *anyopaque) void {
    _ = ctx;
}

pub fn resize(self: *Editor, size: sizepkg.Size) void {
    {
        self.shared_state.mutex.lock();
        defer self.shared_state.mutex.unlock();

        self.shared_state.screen.resize(size);
    }

    self.writeScreen();
}

pub fn selectEntry(self: *Editor, id: u64) !void {
    if (self.buffer) |curr| {
        if (curr.entry_id == id) return;
    }

    if (self.project.buffer_store.open(id)) |buffer| {
        self.buffer = buffer;
        self.writeScreen();
    }
}

pub fn writeScreen(self: *Editor) void {
    const buffer = self.buffer orelse return;

    if (buffer.getState() == .ready) {
        //NOTE:
        //we should write to our screen
    }
}
