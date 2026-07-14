const std = @import("std");
const Allocator = std.mem.Allocator;

const chunk_pool = @import("../chunk_pool.zig");
const ChunkAllocator = chunk_pool.ChunkAllocator;
const chunked_path = @import("../chunked_path.zig");
const ChunkedPath = chunked_path.ChunkedPath;
const datastruct = @import("../datastruct.zig");
const btree = datastruct.btree;
const Io = std.Io;
const File = Io.File;

pub const Entry = struct {
    id: u64,
    path: ChunkedPath,
    kind: File.Kind,
    size: u64,
    mtime: Io.Timestamp,
    inode: u64,
};

pub const NODE_SIZE = Entries.NODE_SIZE;

const Entries = btree.BPlusTree(ChunkedPath, Entry, ChunkedPath.cmp);

const Snapshot = @This();

entries: Entries,

abs_root: []const u8,
root_name: []const u8,
chunk: Allocator,

pub fn init(self: *Snapshot, abs_root: []const u8, root_name: []const u8, chunk: Allocator) !void {
    self.* = .{
        .abs_root = abs_root,
        .root_name = root_name,
        .entries = undefined,
        .chunk = chunk,
    };

    try self.entries.init(self.chunk);
}

pub fn clone(self: *const Snapshot) !Snapshot {
    var copy: Snapshot = .{
        .abs_root = self.abs_root,
        .root_name = self.root_name,
        .entries = undefined,
        .chunk = self.chunk,
    };

    copy.entries = try self.entries.clone(self.chunk);

    return copy;
}

pub fn insert(self: *Snapshot, entry: Entry) !void {
    _ = try self.entries.insert(self.chunk, entry.path, entry);
}

pub fn deinit(self: *Snapshot) void {
    self.entries.deinit(self.chunk);
}
