const std = @import("std");
const Allocator = std.mem.Allocator;

const chunk_pool = @import("../chunk_pool.zig");
const ChunkAllocator = chunk_pool.ChunkAllocator;
const chunked_path = @import("../chunked_path.zig");
const ChunkedPath = chunked_path.ChunkedPath;
const datastruct = @import("../datastruct.zig");
const btree = datastruct.btree;

pub const Entry = struct {
    id: u64,
    path: ChunkedPath,
};

const Entries = btree.BPlusTree(ChunkedPath, Entry, ChunkedPath.cmp);

const Snapshot = @This();

entries: Entries,

abs_root: []const u8,
root_name: []const u8,
chunks: ChunkAllocator,

pub fn init(self: *Snapshot, abs_root: []const u8, root_name: []const u8, alloc: Allocator) !void {
    self.* = .{
        .abs_root = abs_root,
        .root_name = root_name,
        .entries = undefined,
        .chunks = undefined,
    };
    try self.chunks.init(alloc, &.{.{ 1024 * 1024, Entries.NODE_SIZE }});

    try self.entries.init(self.chunks.allocator());
}

pub fn clone(self: *const Snapshot, alloc: Allocator) !Snapshot {
    var copy: Snapshot = .{
        .abs_root = self.abs_root,
        .root_name = self.root_name,
        .entries = undefined,
        .chunks = undefined,
    };
    try copy.chunks.init(alloc, &.{.{ @as(u32, @intCast(self.entries.count)), Entries.NODE_SIZE }});
    copy.entries = try self.entries.clone(copy.chunks.allocator());

    return copy;
}

pub fn insert(self: *Snapshot, entry: Entry) !void {
    _ = try self.entries.insert(self.chunks.allocator(), entry.path, entry);
}

pub fn deinit(self: *Snapshot, alloc: Allocator) void {
    self.chunks.deinit(alloc);
}
