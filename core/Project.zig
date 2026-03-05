const std = @import("std");

const BufferStore = @import("./buffer/BufferStore.zig");
const Buffer = @import("buffer/Buffer.zig");
const Io = @import("./io/mod.zig");
const Monitor = @import("./monitor/mod.zig");
const Worktree = @import("./worktree/mod.zig").Worktree;

const Project = @This();

worktree: *Worktree,
buffer_store: BufferStore,

pub fn create(alloc: std.mem.Allocator, monitor: *Monitor, io: *Io, abs_path: []const u8) !*Project {
    const project = try alloc.create(Project);
    errdefer alloc.destroy(project);

    const worktree = try Worktree.create(abs_path, monitor, alloc);
    errdefer worktree.destroy();

    project.* = .{
        .worktree = worktree,
        .buffer_store = BufferStore.init(alloc, io, worktree),
    };

    return project;
}

pub fn openBuffer(self: *Project, entry_id: u64) ?*Buffer {
    return self.buffer_store.open(entry_id);
}

pub fn destroy(self: *Project, alloc: std.mem.Allocator) void {
    self.buffer_store.deinit();
    self.worktree.destroy();
    alloc.destroy(self);
}
