const std = @import("std");
const Worktree = @import("../worktree/mod.zig").Worktree;
const BufferStore = @import("../buffer/BufferStore.zig");
const EventQueue = @import("../EventQueue.zig");

const Project = @This();

worktree: *Worktree,
buffer_store: BufferStore,

selected_entry: ?u64 = null,

pub fn create(alloc: std.mem.Allocator, abs_path: []const u8, events: *EventQueue) !*Project {
    const project = try alloc.create(Project);
    errdefer alloc.destroy(project);

    const worktree = try Worktree.create(abs_path, alloc, events);
    errdefer worktree.destroy();

    project.* = .{
        .worktree = worktree,
        .buffer_store = BufferStore.init(alloc, &project.worktree.io, events),
    };

    return project;
}

pub fn destroy(self: *Project, alloc: std.mem.Allocator) void {
    self.buffer_store.deinit();
    self.worktree.destroy();
    alloc.destroy(self);
}
