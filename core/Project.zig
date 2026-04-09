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
        .buffer_store = BufferStore.init(alloc, app.io, worktree),
    };

    try global.state.events.on(.ioReadComplete, .{
        .ctx = project,
        .handle = handleIoReadComplete,
    });

    return project;
}

pub fn openBuffer(self: *Project, entry_id: u64) ?*Buffer {
    return self.buffer_store.open(entry_id);
}

pub fn destroy(self: *Project, alloc: std.mem.Allocator) void {
    global.state.events.off(.ioReadComplete, .{
        .ctx = self,
        .handle = handleIoReadComplete,
    });

    self.buffer_store.deinit();
    self.filetree.destroy();
    self.worktree.destroy();
    alloc.destroy(self);
}

fn handleIoReadComplete(ctx: *anyopaque, event: global.GlobalEvents) void {
    const self: *Project = @ptrCast(@alignCast(ctx));
    const payload = event.ioReadComplete;
    const store = self.buffer_store;

    var it = store.buffers.iterator();
    while (it.next()) |entry| {
        const entry_id = entry.key_ptr.*;
        const buf = entry.value_ptr;

        const abs_path = store.worktree.getAbsPath(entry_id) orelse continue;
        if (!std.mem.eql(u8, abs_path, payload.path)) continue;

        if (payload.file) |f| {
            buf.applyFile(f);
        } else {
            buf.applyError();
        }
        global.state.emitGlobal(.{ .bufferUpdate = entry_id });
        return;
    }


}
