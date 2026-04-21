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

    var store = try BufferStore.init(alloc, worktree, app.thread_pool);
    errdefer store.deinit();

    project.* = .{
        .app = app,
        .worktree = worktree,
        .filetree = filetree,
        .buffer_store = store,
    };

    {
        app.settings.rwlock.lockShared();
        defer app.settings.rwlock.unlockShared();

        project.buffer_store.setRuntimeTheme(app.settings.theme_json);
    }

    try global.state.events.on(.ioReadComplete, .{
        .ctx = project,
        .handle = ioRead,
    });

    try global.state.events.on(.themeUpdate, .{
        .ctx = project,
        .handle = themeUpdate,
    });

    return project;
}

pub fn ioRead(ctx: *anyopaque, event: global.GlobalEvents) void {
    const self: *Project = @ptrCast(@alignCast(ctx));
    const data = event.ioReadComplete;

    self.buffer_store.fileLoaded(data.path, data.file);
}

pub fn themeUpdate(ctx: *anyopaque, _: global.GlobalEvents) void {
    const self: *Project = @ptrCast(@alignCast(ctx));

    {
        self.app.settings.rwlock.lockShared();
        defer self.app.settings.rwlock.unlockShared();

        self.buffer_store.setRuntimeTheme(self.app.settings.theme_json);
    }
}

pub fn openBuffer(self: *Project, entry_id: u64) ?*Buffer {
    return self.buffer_store.open(entry_id) catch null;
}

pub fn destroy(self: *Project, alloc: std.mem.Allocator) void {
    global.state.events.off(.ioReadComplete, .{
        .ctx = self,
        .handle = ioRead,
    });

    global.state.events.off(.themeUpdate, .{
        .ctx = self,
        .handle = themeUpdate,
    });

    self.buffer_store.deinit();
    self.filetree.destroy();
    self.worktree.destroy();
    alloc.destroy(self);
}
