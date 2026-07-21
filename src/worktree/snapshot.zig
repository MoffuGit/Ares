const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const File = Io.File;
const atomic = std.atomic;
const heap = std.heap;

const chunk_pool = @import("../chunk_pool.zig");
const ChunkAllocator = chunk_pool.ChunkAllocator;
const chunked_path = @import("../chunked_path.zig");
const ChunkedPath = chunked_path.ChunkedPath;
const ChunkedPathStore = chunked_path.ChunkedPathStore;
const datastruct = @import("../datastruct.zig");
const btree = datastruct.btree;

const Entries = btree.BPlusTree(ChunkedPath, Entry, ChunkedPath.cmp);

const contants = @import("../contants.zig");
const SIMD_CHUNK_BYTES = contants.SIMD_CHUNK_BYTES;
const INLINE_CHUNKS = contants.INLINE_CHUNKS;
const MAX_PATH_LEN = contants.MAX_PATH_LEN;

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

    try self.paths.init(
        io,
        arena,
        .{
            .chunk_capacity = 1024 * 1024,
            .inline_capacity = 1024 * 1024,
        },
    );

    try self.chunks.init(arena, &.{.{
        1024 * 1024, NODE_SIZE,
    }});

    try self.entries.init(self.chunks.allocator());
}

pub fn insert(self: *Snapshot, path: ChunkedPath, meta: Meta) void {
    _ = self.entries.insert(self.chunks.allocator(), path, .{
        .path = path,
        .meta = meta,
        .id = self.next_entry_id.fetchAdd(1, .monotonic),
    }) catch @panic("Snapshot Nodes Overflow");
}

/// Produce a fully independent copy of the snapshot.
///
/// The path store (SIMD chunk pool + dedup map + inline chunk allocator) and
/// the btree node chunk allocator are recreated so the clone shares no
/// allocations with the source. The btree structure is cloned, then every
/// entry is walked to re-intern its `ChunkedPath` into the cloned path store,
/// rebinding both the key and the value's `path` field. After this the clone
/// can outlive and be `deinit`ed independently of the source.
pub fn clone(self: *const Snapshot) !Snapshot {
    var copy: Snapshot = .{
        .io = self.io,
        .arena = .init(self.arena.child_allocator),
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

    // Size the cloned path store from the source's actual usage so we do not
    // pre-allocate the full 1M-chunk capacity on every clone.
    const unique_chunks: u32 = @intCast(self.paths.chunkCount());

    var inline_nodes: usize = 0;
    {
        var count_it = self.entries.iter();
        while (count_it.next()) |kv| {
            const path_chunks = (kv.key.len + SIMD_CHUNK_BYTES - 1) / SIMD_CHUNK_BYTES;
            inline_nodes += (path_chunks + INLINE_CHUNKS - 1) / INLINE_CHUNKS;
        }
    }

    try copy.paths.init(
        self.io,
        arena,
        .{
            .chunk_capacity = @max(unique_chunks, 1),
            .inline_capacity = @max(@as(u32, @intCast(inline_nodes)), 1),
        },
    );

    // The btree node allocator only needs to hold the cloned tree.
    const node_capacity: u32 = @max(@as(u32, @intCast(self.entries.count / 4 + 64)), 256);
    try copy.chunks.init(arena, &.{.{ node_capacity, NODE_SIZE }});

    copy.entries = try self.entries.clone(copy.chunks.allocator());

    // Re-intern every entry's path into the cloned store and rebind the key
    // and value so neither references the source's path store.
    const Rebind = struct {
        fn cb(
            paths: *ChunkedPathStore,
            key: *ChunkedPath,
            value: *Entry,
        ) void {
            var buf: [MAX_PATH_LEN]u8 = undefined;
            const len = key.write(&buf);
            const new_path = paths.put(buf[0..len], key.filename_offset);
            key.* = new_path;
            value.path = new_path;
        }
    };

    copy.entries.forEachMut(&copy.paths, Rebind.cb);

    return copy;
}

pub fn deinit(self: *Snapshot) void {
    self.arena.deinit();
}
