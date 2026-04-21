const std = @import("std");
const Allocator = std.mem.Allocator;
const Buffer = @import("Buffer.zig");
const Io = @import("io/mod.zig");
const Settings = @import("settings/mod.zig");
const Worktree = @import("worktree/mod.zig").Worktree;
const global = @import("global.zig");
const xev_pkg = @import("xev");

const log = std.log.scoped(.buffer_store);

pub const BufferStore = @This();

alloc: Allocator,

rwlock: std.Thread.RwLock = .{},
buffers: std.AutoHashMap(u64, Buffer),
path_to_id: std.StringHashMapUnmanaged(u64) = .{},
worktree: *Worktree,
settings: *Settings,

pub fn init(alloc: Allocator, settings: *Settings, worktree: *Worktree, _: *xev_pkg.ThreadPool) !BufferStore {
    return .{
        .alloc = alloc,
        .buffers = std.AutoHashMap(u64, Buffer).init(alloc),
        .worktree = worktree,
        .settings = settings,
    };
}

pub fn deinit(self: *BufferStore) void {
    var it = self.buffers.valueIterator();
    while (it.next()) |buf| {
        buf.deinit();
    }
    self.buffers.deinit();
    self.path_to_id.clearAndFree(self.alloc);
}

pub fn open(self: *BufferStore, id: u64) ?*Buffer {
    {
        self.rwlock.lockShared();
        defer self.rwlock.unlockShared();

        if (self.get(id)) |buf| return buf;
    }

    self.rwlock.lock();
    defer self.rwlock.unlock();

    const path = self.worktree.loadFile(id) catch return null;

    var buffer = Buffer.init(self.alloc, id);
    buffer.setState(.loading);

    self.buffers.put(id, buffer) catch return null;
    _ = self.path_to_id.fetchPut(self.alloc, path, id) catch return null;

    return self.get(id);
}

pub fn fileLoaded(self: *BufferStore, path: []const u8, file: ?Io.File) void {
    self.rwlock.lockShared();
    defer self.rwlock.unlockShared();

    const id = self.path_to_id.get(path) orelse return;
    const buffer = self.buffers.getPtr(id) orelse return;

    buffer.fileUpdate(file) catch {};
}

pub fn get(self: *BufferStore, entry_id: u64) ?*Buffer {
    return self.buffers.getPtr(entry_id);
}

pub fn close(self: *BufferStore, entry_id: u64) void {
    if (self.buffers.fetchRemove(entry_id)) |kv| {
        var buf = kv.value;
        buf.deinit();
    }
}
