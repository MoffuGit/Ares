const std = @import("std");
const Allocator = std.mem.Allocator;
const Buffer = @import("Buffer.zig");
const Io = @import("../io/mod.zig");
const Worktree = @import("../worktree/mod.zig").Worktree;

const log = std.log.scoped(.buffer_store);

pub const BufferStore = @This();

const ReadContext = struct {
    store: *BufferStore,
    entry_id: u64,
};

alloc: Allocator,
buffers: std.AutoHashMap(u64, Buffer),
io: *Io,
worktree: *Worktree,

pub fn init(alloc: Allocator, io: *Io, worktree: *Worktree) BufferStore {
    return .{
        .alloc = alloc,
        .buffers = std.AutoHashMap(u64, Buffer).init(alloc),
        .io = io,
        .worktree = worktree,
    };
}

pub fn deinit(self: *BufferStore) void {
    var it = self.buffers.valueIterator();
    while (it.next()) |buf| {
        buf.deinit();
    }
    self.buffers.deinit();
}

pub fn open(self: *BufferStore, entry_id: u64) ?*Buffer {
    if (self.get(entry_id)) |buf| return buf;

    const abs_path = self.worktree.getAbsPath(entry_id) orelse return null;
    self.buffers.put(entry_id, Buffer.initLoading(entry_id)) catch |err| {
        log.err("failed to create buffer for entry_id={}: {}", .{ entry_id, err });
        return null;
    };

    self.io.readFile(abs_path, Buffer, self.get(entry_id), readCallback) catch return null;

    return self.get(entry_id);
}

fn readCallback(bufffer: ?*Buffer, file: ?Io.File) void {
    const buf = bufffer orelse return;
    if (file) |f| {
        buf.applyFile(f);
    } else {
        buf.applyError();
    }
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
