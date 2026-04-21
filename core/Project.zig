const std = @import("std");

const BufferStore = @import("BufferStore.zig");
const Buffer = @import("Buffer.zig");
const Io = @import("io/mod.zig");
const Monitor = @import("monitor/mod.zig");
const Worktree = @import("worktree/mod.zig").Worktree;
const FileTree = @import("filetree.zig");
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

    const worktree = try Worktree.create(abs_path, app.io, app.monitor, alloc);
    errdefer worktree.destroy();

    const filetree = try FileTree.create(alloc, worktree);
    errdefer filetree.destroy();

    var store = try BufferStore.init(alloc, app.settings, worktree, app.thread_pool);
    errdefer store.deinit();

    project.* = .{
        .app = app,
        .worktree = worktree,
        .filetree = filetree,
        .buffer_store = store,
    };

    try global.state.events.on(.ioReadComplete, .{
        .ctx = project,
        .handle = ioRead,
    });

    return project;
}

pub fn ioRead(ctx: *anyopaque, event: global.GlobalEvents) void {
    const self: *Project = @ptrCast(@alignCast(ctx));
    const data = event.ioReadComplete;

    self.buffer_store.fileLoaded(data.path, data.file);
}

pub fn openBuffer(self: *Project, entry_id: u64) ?*Buffer {
    return self.buffer_store.open(entry_id);
}

pub fn destroy(self: *Project, alloc: std.mem.Allocator) void {
    global.state.events.off(.ioReadComplete, .{
        .ctx = self,
        .handle = ioRead,
    });

    self.buffer_store.deinit();
    self.filetree.destroy();
    self.worktree.destroy();
    alloc.destroy(self);
}
