const std = @import("std");

const BufferStore = @import("./buffer/BufferStore.zig");
const Buffer = @import("buffer/Buffer.zig");
const Io = @import("./io/mod.zig");
const Monitor = @import("./monitor/mod.zig");
const Worktree = @import("./worktree/mod.zig").Worktree;
const FileTree = @import("filetree/mod.zig");
const App = @import("App.zig");
const global = @import("global.zig");

const Project = @This();

app: *App,
worktree: *Worktree,
filetree: *FileTree,
buffer_store: BufferStore,

pub fn create(alloc: std.mem.Allocator, app: *App, abs_path: []const u8) !*Project {
    const project = try alloc.create(Project);
    errdefer alloc.destroy(project);

    const worktree = try Worktree.create(abs_path, app.monitor, alloc);
    errdefer worktree.destroy();

    const filetree = try FileTree.create(alloc, worktree);
    errdefer filetree.destroy();

    project.* = .{
        .app = app,
        .worktree = worktree,
        .filetree = filetree,
        .buffer_store = try BufferStore.init(alloc, app.io, worktree, app.thread_pool),
    };

    try project.buffer_store.start();

    return project;
}

pub fn openBuffer(self: *Project, entry_id: u64) ?*Buffer {
    return self.buffer_store.open(entry_id);
}

pub fn destroy(self: *Project, alloc: std.mem.Allocator) void {
    self.buffer_store.deinit();
    self.filetree.destroy();
    self.worktree.destroy();
    alloc.destroy(self);
}
