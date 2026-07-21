const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const File = Io.File;
const atomic = std.atomic;
const heap = std.heap;

const chunk_pool = @import("../chunk_pool.zig");
const ChunkAllocator = chunk_pool.ChunkAllocator;
const ChunkedPathStore = @import("../chunked_path.zig");
const ChunkedPath = ChunkedPathStore.ChunkedPath;
const INLINE_NODE_SIZE = ChunkedPathStore.INLINE_NODE_SIZE;
const contants = @import("../contants.zig");
const SIMD_CHUNK_BYTES = contants.SIMD_CHUNK_BYTES;
const INLINE_CHUNKS = contants.INLINE_CHUNKS;
const MAX_PATH_LEN = contants.MAX_PATH_LEN;
const datastruct = @import("../datastruct.zig");
const btree = datastruct.btree;

const Entries = btree.BPlusTree(ChunkedPath, Entry, ChunkedPath.cmp);

pub const Entry = struct {
    id: u64,
    path: ChunkedPath,
    meta: Meta,
};

pub const Meta = struct {
    mtime: Io.Timestamp,
    size: u64,
    inode: u64,
    kind: File.Kind,
    hidden: bool,
    ignored: bool,
};

pub const NODE_SIZE = Entries.NODE_SIZE;

const Snapshot = @This();

io: Io,
arena: heap.ArenaAllocator,
chunks: ChunkAllocator,

paths: ChunkedPathStore,
entries: Entries,

abs_root: []u8,
root_name: []u8,

next_entry_id: atomic.Value(u64),

pub fn init(
    self: *Snapshot,
    abs_path: []const u8,
    gpa: Allocator,
    io: Io,
) !void {
    self.* = .{
        .io = io,
        .arena = .init(gpa),
        .chunks = undefined,
        .abs_root = undefined,
        .root_name = undefined,
        .entries = undefined,
        .paths = undefined,
        .next_entry_id = .init(0),
    };

    const arena = self.arena.allocator();
    errdefer self.arena.deinit();

    self.abs_root = try arena.dupe(u8, abs_path);
    self.root_name = try arena.dupe(u8, std.fs.path.basename(self.abs_root));

    try self.paths.init(io, arena, 1024 * 1024);

    try self.chunks.init(arena, &.{
        .{ 1024 * 1024, NODE_SIZE },
        .{ 1024 * 1024, INLINE_NODE_SIZE },
    });

    try self.entries.init(self.chunks.allocator());
}

pub fn insert(self: *Snapshot, path: ChunkedPath, meta: Meta) void {
    _ = self.entries.insert(self.chunks.allocator(), path, .{
        .path = path,
        .meta = meta,
        .id = self.next_entry_id.fetchAdd(1, .monotonic),
    }) catch @panic("Snapshot Nodes Overflow");
}

pub fn newPath(self: *Snapshot, path: []const u8, offset: u32) ChunkedPath {
    return self.paths.put(path, offset, self.chunks.allocator());
}

pub fn appendToPath(
    self: *Snapshot,
    path: ChunkedPath,
    suffix: []const u8,
    offset: u32,
) ChunkedPath {
    return self.paths.append(path, suffix, offset, self.chunks.allocator());
}

pub fn clone(self: *const Snapshot, gpa: Allocator) !Snapshot {
    var copy: Snapshot = .{
        .io = self.io,
        .arena = .init(gpa),
        .chunks = undefined,
        .paths = undefined,
        .entries = undefined,
        .abs_root = undefined,
        .root_name = undefined,
        .next_entry_id = .init(self.next_entry_id.load(.monotonic)),
    };
    errdefer copy.arena.deinit();
    const arena = copy.arena.allocator();

    copy.abs_root = try arena.dupe(u8, self.abs_root);
    copy.root_name = try arena.dupe(u8, self.root_name);

    try copy.chunks.init(arena, &.{
        .{ 1024 * 1024, NODE_SIZE },
        .{ 1024 * 1024, INLINE_NODE_SIZE },
    });
    copy.entries = try self.entries.clone(copy.chunks.allocator());

    try copy.paths.init(self.io, arena, 1024 * 1024);

    var iter = copy.entries.iter();
    var buf: [MAX_PATH_LEN]u8 = undefined;
    while (iter.next_mut()) |entry| {
        const len = entry.key.write(&buf);
        const new_path = copy.paths.put(buf[0..len], entry.key.filename_offset, copy.chunks.allocator());
        entry.key.* = new_path;
        entry.value.path = new_path;
    }

    return copy;
}

pub fn deinit(self: *Snapshot) void {
    self.arena.deinit();
}
