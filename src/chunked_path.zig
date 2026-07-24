const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const testing = std.testing;
const Io = std.Io;
const math = std.math;
const heap = std.heap;

const datastruct = @import("datastruct.zig");
const DoublyLinkedList = datastruct.DoublyLinkedList;
const chunk_pool = @import("chunk_pool.zig");
const ChunkPool = chunk_pool.ChunkPool;
const constans = @import("contants.zig");
const SIMD_CHUNK_BYTES = constans.SIMD_CHUNK_BYTES;
const INLINE_CHUNKS = constans.INLINE_CHUNKS;
const MAX_PATH_LEN = constans.MAX_PATH_LEN;

pub const INLINE_NODE_SIZE = @sizeOf(InlineChunks);

pub const Chunk = [SIMD_CHUNK_BYTES]u8;
const SharedChunk = struct { index: ChunkPool.Index, ref_count: usize };
pub const InlineChunks = struct {
    next: ?*InlineChunks = null,
    prev: ?*InlineChunks = null,
    chunks: [INLINE_CHUNKS]ChunkPool.Index,
};

pub const ChunkedPathStore = @This();

io: Io,
mutex: Io.Mutex,
pool: ChunkPool,
dedup: std.AutoHashMap(Chunk, SharedChunk),

pub fn init(self: *ChunkedPathStore, io: Io, allocator: Allocator, capacity: u32) !void {
    self.* = .{
        .io = io,
        .mutex = .init,
        .pool = undefined,
        .dedup = undefined,
    };

    try self.pool.init(allocator, capacity, SIMD_CHUNK_BYTES);
    errdefer self.pool.deinit(allocator);

    self.dedup = .init(allocator);
    errdefer self.dedup.deinit();

    try self.dedup.ensureTotalCapacity(capacity);
}

pub fn lock(self: *ChunkedPathStore) void {
    self.mutex.lockUncancelable(self.io);
}

pub fn unlock(self: *ChunkedPathStore) void {
    self.mutex.unlock(self.io);
}

pub fn deinit(self: *ChunkedPathStore, allocator: Allocator) void {
    self.dedup.deinit();
    self.pool.deinit(allocator);
}

fn chunkCount(self: *const ChunkedPathStore) usize {
    return self.dedup.count();
}

pub fn put(self: *ChunkedPathStore, path: []const u8, filename_offset: u32, alloc: Allocator) ChunkedPath {
    assert(path.len <= MAX_PATH_LEN);
    assert(filename_offset < path.len);
    assert(path.len > 0);

    const total_chunks = (path.len + SIMD_CHUNK_BYTES - 1) / SIMD_CHUNK_BYTES;
    const total_nodes = (total_chunks + INLINE_CHUNKS - 1) / INLINE_CHUNKS;

    var chunks: DoublyLinkedList(InlineChunks) = .{};
    {
        var i: usize = 0;
        while (i < total_nodes) : (i += 1) {
            chunks.append(alloc.create(InlineChunks) catch @panic("Inline Chunks Overflow"));
        }
    }

    var node = chunks.first orelse unreachable;
    var slot: usize = 0;
    var chunks_interned: usize = 0;
    var offset: usize = 0;

    while (offset < path.len) {
        var canonical: Chunk = [_]u8{0} ** SIMD_CHUNK_BYTES;
        const end = @min(offset + SIMD_CHUNK_BYTES, path.len);
        const chunk_len = end - offset;

        @memcpy(canonical[0..chunk_len], path[offset..end]);

        const chunk_index = self.internChunk(canonical);

        node.chunks[slot] = chunk_index;
        chunks_interned += 1;
        slot += 1;

        if (slot >= INLINE_CHUNKS) {
            slot = 0;
            if (node.next) |next| node = next;
        }

        offset = end;
    }

    return .{
        .len = @intCast(path.len),
        .filename_offset = filename_offset,
        .chunks = chunks,
        .pool = &self.pool,
    };
}

pub fn append(
    self: *ChunkedPathStore,
    existing: ChunkedPath,
    suffix: []const u8,
    filename_offset: u32,
    alloc: Allocator,
) ChunkedPath {
    assert(existing.len > 0);
    assert(suffix.len > 0);

    var buffer: [MAX_PATH_LEN]u8 = undefined;
    const len: u32 = @intCast(existing.path(&buffer).len);
    const new_len = len + suffix.len;
    const new_offset = len + filename_offset;

    @memcpy(buffer[len..new_len], suffix);

    return self.put(buffer[0..new_len], new_offset, alloc);
}

pub fn free(self: *ChunkedPathStore, chunked_path: *ChunkedPath, alloc: Allocator) void {
    assert(chunked_path.len > 0);

    const total_chunks = (chunked_path.len + SIMD_CHUNK_BYTES - 1) / SIMD_CHUNK_BYTES;

    assert(total_chunks > 0);

    var released: usize = 0;

    var node = chunked_path.chunks.first;
    while (node) |n| {
        const next = n.next;
        const len = @min(INLINE_CHUNKS, total_chunks - released);
        for (n.chunks[0..len]) |chunk_index| {
            self.destroyChunk(chunk_index);
        }
        released += len;
        alloc.destroy(n);
        node = next;
    }
}

fn internChunk(self: *ChunkedPathStore, canonical: Chunk) ChunkPool.Index {
    self.lock();
    defer self.unlock();

    if (self.dedup.getPtr(canonical)) |entry| {
        entry.ref_count += 1;
        return entry.index;
    }

    const index = self.pool.allocIndex() orelse @panic("SIMD CHUNK Overflow");
    resolveChunk(&self.pool, index).* = canonical;

    self.dedup.putAssumeCapacity(canonical, .{ .index = index, .ref_count = 1 });

    return index;
}

fn destroyChunk(self: *ChunkedPathStore, index: ChunkPool.Index) void {
    self.lock();
    defer self.unlock();

    const key: Chunk = resolveChunk(&self.pool, index).*;
    const entry = self.dedup.getPtr(key) orelse unreachable;
    assert(entry.index == index);

    if (entry.ref_count > 1) {
        entry.ref_count -= 1;
    } else {
        _ = self.dedup.remove(key);
        self.pool.freeIndex(index);
    }
}

fn resolveChunk(pool: *ChunkPool, index: ChunkPool.Index) *Chunk {
    const bytes = pool.sliceFromIndex(index) orelse @panic("invalid SIMD chunk index");
    assert(bytes.len == SIMD_CHUNK_BYTES);
    return @ptrCast(@alignCast(bytes.ptr));
}

pub const ChunkedPath = struct {
    len: u32,
    filename_offset: u32,
    chunks: DoublyLinkedList(InlineChunks),
    pool: *ChunkPool,

    pub const Iterator = struct {
        node: ?*const InlineChunks,
        index: usize,
        remaining: u32,
        pool: *ChunkPool,

        pub fn next(self: *Iterator) ?[]const u8 {
            if (self.remaining == 0) return null;

            const node: *const InlineChunks = self.node orelse return null;

            const chunk = resolveChunk(self.pool, node.chunks[self.index]);

            if (self.remaining >= SIMD_CHUNK_BYTES) {
                self.remaining -= SIMD_CHUNK_BYTES;
                self.index += 1;

                if (self.index == INLINE_CHUNKS) {
                    self.index = 0;
                    self.node = node.next;
                }

                return chunk[0..SIMD_CHUNK_BYTES];
            } else {
                const result: []const u8 = chunk[0..self.remaining];

                self.remaining = 0;

                return result;
            }
        }
    };

    pub const ReverseIterator = struct {
        node: ?*const InlineChunks,
        index: usize,
        remaining: u32,
        pool: *ChunkPool,

        pub fn next(self: *ReverseIterator) ?[]const u8 {
            if (self.remaining == 0) return null;

            const node: *const InlineChunks = self.node orelse return null;

            const chunk = resolveChunk(self.pool, node.chunks[self.index]);

            const rem = self.remaining % SIMD_CHUNK_BYTES;

            const take: usize = if (rem == 0) SIMD_CHUNK_BYTES else rem;
            const result: []const u8 = chunk[0..take];

            self.remaining -= @intCast(take);

            if (self.index == 0) {
                self.index = INLINE_CHUNKS - 1;
                self.node = node.prev;
            } else {
                self.index -= 1;
            }

            return result;
        }
    };

    pub fn iterator(self: *const ChunkedPath) Iterator {
        return .{
            .node = self.chunks.first,
            .index = 0,
            .remaining = self.len,
            .pool = self.pool,
        };
    }

    pub fn reverse_iterator(self: *const ChunkedPath) ReverseIterator {
        const chunks = (self.len + SIMD_CHUNK_BYTES - 1) / SIMD_CHUNK_BYTES;

        return .{
            .node = self.chunks.last,
            .index = (chunks - 1) % INLINE_CHUNKS,
            .remaining = self.len,
            .pool = self.pool,
        };
    }

    pub fn path(self: ChunkedPath, buffer: []u8) []u8 {
        assert(buffer.len >= self.len);

        var it = self.iterator();
        var offset: usize = 0;
        var remaining: usize = self.len;

        while (it.next()) |segment| {
            if (remaining == 0) break;
            const take = @min(segment.len, remaining);
            @memcpy(buffer[offset .. offset + take], segment[0..take]);
            offset += take;
            remaining -= take;
        }

        return buffer[0..self.len];
    }

    pub fn basename(self: ChunkedPath, buffer: []u8) []u8 {
        const name_len: usize = self.len - self.filename_offset;
        assert(buffer.len >= name_len);

        var it = self.reverse_iterator();
        var offset: usize = @intCast(name_len);
        while (it.next()) |segment| {
            if (offset == 0) break;
            const take: usize = @min(segment.len, offset);
            @memcpy(buffer[offset - take .. offset], segment[segment.len - take .. segment.len]);
            offset -= take;
        }

        return buffer[0..name_len];
    }

    pub fn slice(self: ChunkedPath, allocator: Allocator) ![]u8 {
        const buf = try allocator.alloc(u8, self.len);
        assert(buf.len == self.path(buf).len);

        return buf;
    }

    pub fn cmp(self: ChunkedPath, other: ChunkedPath) math.Order {
        if (self.len == 0 and other.len == 0) return .eq;
        if (self.len == 0) return .lt;
        if (other.len == 0) return .gt;

        const Vec = @Vector(SIMD_CHUNK_BYTES, u8);
        const MaskInt = std.meta.Int(.unsigned, SIMD_CHUNK_BYTES);
        const all_ones: MaskInt = @as(MaskInt, 0) -% 1;

        var node_a = self.chunks.first;
        var node_b = other.chunks.first;
        var slot_a: usize = 0;
        var slot_b: usize = 0;
        var remaining_a: u32 = self.len;
        var remaining_b: u32 = other.len;

        while (remaining_a > 0 and remaining_b > 0) {
            const chunk_a: *Chunk = resolveChunk(self.pool, node_a.?.chunks[slot_a]);
            const chunk_b: *Chunk = resolveChunk(other.pool, node_b.?.chunks[slot_b]);

            const a_vec: Vec = chunk_a.*;
            const b_vec: Vec = chunk_b.*;
            const eq = a_vec == b_vec;
            const mask: MaskInt = @bitCast(eq);

            if (mask != all_ones) {
                const first_diff = @ctz(~mask);

                const a_byte = chunk_a[first_diff];
                const b_byte = chunk_b[first_diff];

                if (a_byte < b_byte) return .lt;

                return .gt;
            }

            remaining_a -= @min(remaining_a, SIMD_CHUNK_BYTES);
            slot_a += 1;

            if (slot_a >= INLINE_CHUNKS) {
                slot_a = 0;
                node_a = node_a.?.next;
            }

            remaining_b -= @min(remaining_b, SIMD_CHUNK_BYTES);
            slot_b += 1;

            if (slot_b >= INLINE_CHUNKS) {
                slot_b = 0;
                node_b = node_b.?.next;
            }
        }

        return math.order(self.len, other.len);
    }
};

test "SIMD_CHUNK_BYTES path" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    const path = "0123456789abcdef";
    var cs = store.put(path, 0, gpa);
    defer store.free(&cs, gpa);

    const bytes = try cs.slice(gpa);
    defer gpa.free(bytes);
    try testing.expectEqualSlices(u8, path, bytes);
}

test "INLINE_CHUNKS path" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    const path = "0123456789abcdef" ++ "GHIJKLMNOPQRSTUV" ++ "WXYZabcdefghijkl" ++ "mnopqrstuvwxyzAB";
    try testing.expectEqual(@as(usize, 64), path.len);

    var cs = store.put(path, 0, gpa);
    defer store.free(&cs, gpa);

    const bytes = try cs.slice(gpa);
    defer gpa.free(bytes);
    try testing.expectEqualSlices(u8, path, bytes);
}

test "Multi INLINE_CHUNKS path" {
    const gpa = testing.allocator;
    const io = testing.io;

    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 64);
    defer store.deinit(gpa);

    const path = "0123456789abcdef" ++ "GHIJKLMNOPQRSTUV" ++ "WXYZabcdefghijkl" ++ "mnopqrstuvwxyzAB" ++ "CDEFGHIJKLMNOPQR";
    try testing.expectEqual(@as(usize, 80), path.len);

    var cs = store.put(path, 0, gpa);
    defer store.free(&cs, gpa);

    try testing.expectEqual(@as(u32, 80), cs.len);
    try testing.expect(cs.chunks.first.?.next != null);
    try testing.expectEqual(@as(?*InlineChunks, null), cs.chunks.first.?.next.?.next);

    const bytes = try cs.slice(gpa);
    defer gpa.free(bytes);
    try testing.expectEqualSlices(u8, path, bytes);
}

test "maximum 4096-byte path" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 256);
    defer store.deinit(gpa);

    var path_buf: [MAX_PATH_LEN]u8 = undefined;
    for (&path_buf, 0..) |*b, i| b.* = @intCast(i % 256);
    const path = path_buf[0..];

    var cs = store.put(path, 0, gpa);
    defer store.free(&cs, gpa);

    try testing.expectEqual(@as(u32, MAX_PATH_LEN), cs.len);

    const bytes = try cs.slice(gpa);
    defer gpa.free(bytes);
    try testing.expectEqualSlices(u8, path, bytes);
}

test "identical chunks shared across paths" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    const shared_prefix = "0123456789abcdef";
    var cs_a = store.put(shared_prefix, 0, gpa);
    defer store.free(&cs_a, gpa);
    var cs_b = store.put(shared_prefix, 0, gpa);
    defer store.free(&cs_b, gpa);

    try testing.expectEqual(cs_a.chunks.first.?.chunks[0], cs_b.chunks.first.?.chunks[0]);
    try testing.expectEqual(@as(usize, 1), store.chunkCount());
}

test "filename offset preserved" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    const path = "src/chunked_string.zig";
    const filename_offset: u32 = @intCast(std.mem.lastIndexOfScalar(u8, path, '/') orelse 0);

    var cs = store.put(path, filename_offset + 1, gpa);
    defer store.free(&cs, gpa);

    try testing.expectEqual(filename_offset + 1, cs.filename_offset);

    const bytes = try cs.slice(gpa);
    defer gpa.free(bytes);
    try testing.expectEqualSlices(u8, path, bytes);
    try testing.expectEqualSlices(u8, "chunked_string.zig", bytes[cs.filename_offset..]);
}

test "iterator over multi-node path" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    const path = "0123456789abcdef" ++ "GHIJKLMNOPQRSTUV" ++ "WXYZabcdefghijkl" ++ "mnopqrstuvwxyzAB" ++ "CDEFGHIJKLMNOPQR";
    var cs = store.put(path, 0, gpa);
    defer store.free(&cs, gpa);

    var it = cs.iterator();
    var offset: usize = 0;
    while (it.next()) |seg| {
        try testing.expectEqualSlices(u8, path[offset .. offset + seg.len], seg);
        offset += seg.len;
    }
    try testing.expectEqual(@as(usize, 80), offset);
}

test "reverse iterator over multi-node path" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    const path = "0123456789abcdef" ++ "GHIJKLMNOPQRSTUV" ++ "WXYZabcdefghijkl" ++ "mnopqrstuvwxyzAB" ++ "CDEFGHIJKLMNOPQR";
    var cs = store.put(path, 0, gpa);
    defer store.free(&cs, gpa);

    var it = cs.reverse_iterator();
    var offset: usize = path.len;
    while (it.next()) |seg| {
        try testing.expectEqualSlices(u8, path[offset - seg.len .. offset], seg);
        offset -= seg.len;
    }
    try testing.expectEqual(@as(usize, 0), offset);
}

test "reverse iterator over partial-chunk path" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    // 20 bytes -> 2 chunks: a full 16-byte chunk and a 4-byte partial chunk.
    const path = "0123456789abcdef" ++ "WXYZ";
    var cs = store.put(path, 0, gpa);
    defer store.free(&cs, gpa);

    var it = cs.reverse_iterator();
    var offset: usize = path.len;
    while (it.next()) |seg| {
        try testing.expectEqualSlices(u8, path[offset - seg.len .. offset], seg);
        offset -= seg.len;
    }
    try testing.expectEqual(@as(usize, 0), offset);
}

test "append short suffix to short path (merges into one chunk)" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    const orig = "hello";
    var cs = store.put(orig, 0, gpa);
    defer store.free(&cs, gpa);

    const suffix = "/world";
    // filename_offset is relative to the suffix: "world" starts at index 1.
    var appended = store.append(cs, suffix, 1, gpa);
    defer store.free(&appended, gpa);

    // Original is unchanged.
    try testing.expectEqual(@as(u32, 5), cs.len);
    const orig_bytes = try cs.slice(gpa);
    defer gpa.free(orig_bytes);
    try testing.expectEqualSlices(u8, orig, orig_bytes);

    // Appended path has the combined content.
    try testing.expectEqual(@as(u32, 11), appended.len);
    try testing.expectEqual(@as(u32, 6), appended.filename_offset);
    const new_bytes = try appended.slice(gpa);
    defer gpa.free(new_bytes);
    try testing.expectEqualSlices(u8, "hello/world", new_bytes);
}

test "append to exact-chunk-boundary path (suffix starts new chunk)" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    const orig = "0123456789abcdef"; // exactly 16 bytes
    var cs = store.put(orig, 0, gpa);
    defer store.free(&cs, gpa);

    // "foo" starts at index 1 within the suffix "/foo".
    var appended = store.append(cs, "/foo", 1, gpa);
    defer store.free(&appended, gpa);

    try testing.expectEqual(@as(u32, 20), appended.len);
    const new_bytes = try appended.slice(gpa);
    defer gpa.free(new_bytes);
    try testing.expectEqualSlices(u8, "0123456789abcdef/foo", new_bytes);

    // The full chunk should be shared between the two paths.
    try testing.expectEqual(cs.chunks.first.?.chunks[0], appended.chunks.first.?.chunks[0]);
}

test "append spanning multiple nodes" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    // 80 bytes = 5 chunks = 2 nodes.
    const orig = "0123456789abcdef" ++ "GHIJKLMNOPQRSTUV" ++ "WXYZabcdefghijkl" ++ "mnopqrstuvwxyzAB" ++ "CDEFGHIJKLMNOPQR";
    var cs = store.put(orig, 0, gpa);
    defer store.free(&cs, gpa);

    const suffix = "/subdir/file.zig";
    const expected = orig ++ suffix;
    // "subdir/file.zig" starts at index 1 within the suffix.
    var appended = store.append(cs, suffix, 1, gpa);
    defer store.free(&appended, gpa);

    try testing.expectEqual(@as(u32, @intCast(expected.len)), appended.len);
    const new_bytes = try appended.slice(gpa);
    defer gpa.free(new_bytes);
    try testing.expectEqualSlices(u8, expected, new_bytes);

    // First 4 full chunks (first node) should be shared.
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        try testing.expectEqual(cs.chunks.first.?.chunks[i], appended.chunks.first.?.chunks[i]);
    }
}

test "append that fills the partial chunk exactly" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    // 10 bytes -> partial chunk with 10/16 used, 6 bytes of padding.
    const orig = "0123456789";
    var cs = store.put(orig, 0, gpa);
    defer store.free(&cs, gpa);

    // Suffix of 6 bytes fills the remainder exactly.
    const suffix = "abcdef";
    // filename starts at index 0 within the suffix.
    var appended = store.append(cs, suffix, 0, gpa);
    defer store.free(&appended, gpa);

    try testing.expectEqual(@as(u32, 16), appended.len);
    const new_bytes = try appended.slice(gpa);
    defer gpa.free(new_bytes);
    try testing.expectEqualSlices(u8, "0123456789abcdef", new_bytes);

    // The merged chunk should be a new canonical chunk (different from orig's partial).
    try testing.expect(cs.chunks.first.?.chunks[0] != appended.chunks.first.?.chunks[0]);
}

test "append preserves original after original is freed" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    const orig = "0123456789abcdef"; // full 16-byte chunk
    var cs = store.put(orig, 0, gpa);

    // "test" starts at index 1 within the suffix "/test".
    var appended = store.append(cs, "/test", 1, gpa);
    defer store.free(&appended, gpa);

    // Free the original; the appended path's shared chunk should still be valid.
    store.free(&cs, gpa);

    const new_bytes = try appended.slice(gpa);
    defer gpa.free(new_bytes);
    try testing.expectEqualSlices(u8, "0123456789abcdef/test", new_bytes);
}

test "append resolves suffix-relative filename_offset to absolute" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    // existing = "src/core" (8 bytes, filename "core" at offset 4)
    const orig = "src/core";
    var cs = store.put(orig, 4, gpa);
    defer store.free(&cs, gpa);

    // suffix = "/module/file.zig" — filename "file.zig" starts at index 8
    // within the suffix (after "/module/").
    const suffix = "/module/file.zig";
    var appended = store.append(cs, suffix, 8, gpa);
    defer store.free(&appended, gpa);

    // Resolved offset should be 8 (existing.len) + 8 = 16.
    try testing.expectEqual(@as(u32, 16), appended.filename_offset);

    const bytes = try appended.slice(gpa);
    defer gpa.free(bytes);
    try testing.expectEqualSlices(u8, "src/core/module/file.zig", bytes);
    try testing.expectEqualSlices(u8, "file.zig", bytes[appended.filename_offset..]);
}
test "cmp equal strings" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    const path = "src/chunked_string.zig";
    var cs_a = store.put(path, 0, gpa);
    defer store.free(&cs_a, gpa);
    var cs_b = store.put(path, 0, gpa);
    defer store.free(&cs_b, gpa);

    try testing.expectEqual(std.math.Order.eq, cs_a.cmp(cs_b));
    try testing.expectEqual(std.math.Order.eq, cs_b.cmp(cs_a));
}

test "cmp differs at first byte" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    var cs_a = store.put("abc", 0, gpa);
    defer store.free(&cs_a, gpa);
    var cs_b = store.put("xbc", 0, gpa);
    defer store.free(&cs_b, gpa);

    try testing.expectEqual(std.math.Order.lt, cs_a.cmp(cs_b));
    try testing.expectEqual(std.math.Order.gt, cs_b.cmp(cs_a));
}

test "cmp differs at last byte of first chunk" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    const path_a = "0123456789abcdeA";
    const path_b = "0123456789abcdeB";
    var cs_a = store.put(path_a, 0, gpa);
    defer store.free(&cs_a, gpa);
    var cs_b = store.put(path_b, 0, gpa);
    defer store.free(&cs_b, gpa);

    try testing.expectEqual(std.math.Order.lt, cs_a.cmp(cs_b));
    try testing.expectEqual(std.math.Order.gt, cs_b.cmp(cs_a));
}

test "cmp differs in second chunk" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    // 32 bytes = 2 chunks. Second chunk differs at first byte.
    const path_a = "0123456789abcdef" ++ "ABCDEFGHIJKLMNOP";
    const path_b = "0123456789abcdef" ++ "aBCDEFGHIJKLMNOP";
    var cs_a = store.put(path_a, 0, gpa);
    defer store.free(&cs_a, gpa);
    var cs_b = store.put(path_b, 0, gpa);
    defer store.free(&cs_b, gpa);

    try testing.expectEqual(std.math.Order.lt, cs_a.cmp(cs_b)); // 'A' (0x41) < 'a' (0x61)
    try testing.expectEqual(std.math.Order.gt, cs_b.cmp(cs_a));
}

test "cmp differs in second node (multi-node)" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    // 80 bytes = 5 chunks = 2 nodes. Difference at chunk 4 (first slot of second node).
    const base = "0123456789abcdef" ++ "GHIJKLMNOPQRSTUV" ++ "WXYZabcdefghijkl" ++ "mnopqrstuvwxyzAB";
    const path_a = base ++ "CDEFGHIJKLMNOPQR";
    const path_b = base ++ "cDEFGHIJKLMNOPQR";
    var cs_a = store.put(path_a, 0, gpa);
    defer store.free(&cs_a, gpa);
    var cs_b = store.put(path_b, 0, gpa);
    defer store.free(&cs_b, gpa);

    try testing.expectEqual(std.math.Order.lt, cs_a.cmp(cs_b)); // 'C' (0x43) < 'c' (0x63)
    try testing.expectEqual(std.math.Order.gt, cs_b.cmp(cs_a));
}

test "cmp prefix — shorter is less" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    var cs_short = store.put("hello", 0, gpa);
    defer store.free(&cs_short, gpa);
    var cs_long = store.put("hello world", 0, gpa);
    defer store.free(&cs_long, gpa);

    try testing.expectEqual(std.math.Order.lt, cs_short.cmp(cs_long));
    try testing.expectEqual(std.math.Order.gt, cs_long.cmp(cs_short));
}

test "cmp prefix across chunk boundary" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    // 16 bytes exactly vs 17 bytes (first chunk identical, second has 1 byte).
    const first_chunk = "0123456789abcdef";
    var cs_16 = store.put(first_chunk, 0, gpa);
    defer store.free(&cs_16, gpa);
    var cs_17 = store.put(first_chunk ++ "x", 0, gpa);
    defer store.free(&cs_17, gpa);

    try testing.expectEqual(std.math.Order.lt, cs_16.cmp(cs_17));
    try testing.expectEqual(std.math.Order.gt, cs_17.cmp(cs_16));
}

test "cmp partial chunk vs full chunk (padding as zero)" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    // "hello" is 5 bytes + 11 zeros in its chunk.
    // "hello\x00world!!!!!" is 16 bytes (contains a real null at index 5).
    // The first chunk has 'w' at index 6 where "hello" has 0 (padding).
    // 0 < 'w', so "hello" < "hello\x00world!!!!!".
    const path_with_null = "hello\x00world!!!!!";
    try testing.expectEqual(@as(usize, 16), path_with_null.len);

    var cs_short = store.put("hello", 0, gpa);
    defer store.free(&cs_short, gpa);
    var cs_full = store.put(path_with_null, 0, gpa);
    defer store.free(&cs_full, gpa);

    try testing.expectEqual(std.math.Order.lt, cs_short.cmp(cs_full));
    try testing.expectEqual(std.math.Order.gt, cs_full.cmp(cs_short));
}

test "cmp long equal paths (multi-node)" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    const path = "0123456789abcdef" ++ "GHIJKLMNOPQRSTUV" ++ "WXYZabcdefghijkl" ++ "mnopqrstuvwxyzAB" ++ "CDEFGHIJKLMNOPQR";
    var cs_a = store.put(path, 0, gpa);
    defer store.free(&cs_a, gpa);
    var cs_b = store.put(path, 0, gpa);
    defer store.free(&cs_b, gpa);

    try testing.expectEqual(std.math.Order.eq, cs_a.cmp(cs_b));
}

test "cmp max length equal" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 256);
    defer store.deinit(gpa);

    var path_buf: [MAX_PATH_LEN]u8 = undefined;
    for (&path_buf, 0..) |*b, i| b.* = @intCast(i % 256);

    var cs_a = store.put(path_buf[0..], 0, gpa);
    defer store.free(&cs_a, gpa);
    var cs_b = store.put(path_buf[0..], 0, gpa);
    defer store.free(&cs_b, gpa);

    try testing.expectEqual(std.math.Order.eq, cs_a.cmp(cs_b));
}

test "cmp max length differ at last byte" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 256);
    defer store.deinit(gpa);

    var path_a: [MAX_PATH_LEN]u8 = undefined;
    var path_b: [MAX_PATH_LEN]u8 = undefined;
    for (&path_a, &path_b, 0..) |*a, *b, i| {
        a.* = @intCast(i % 256);
        b.* = @intCast(i % 256);
    }
    path_a[MAX_PATH_LEN - 1] = 0;
    path_b[MAX_PATH_LEN - 1] = 1;

    var cs_a = store.put(path_a[0..], 0, gpa);
    defer store.free(&cs_a, gpa);
    var cs_b = store.put(path_b[0..], 0, gpa);
    defer store.free(&cs_b, gpa);

    try testing.expectEqual(std.math.Order.lt, cs_a.cmp(cs_b));
    try testing.expectEqual(std.math.Order.gt, cs_b.cmp(cs_a));
}

test "cmp matches std.mem.order on random paths" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    const test_paths = [_][]const u8{
        "a",
        "ab",
        "abc",
        "abcd",
        "abcde",
        "abcdef",
        "abcdefg",
        "abcdefgh",
        "abcdefghi",
        "abcdefghij",
        "abcdefghijk",
        "abcdefghijkl",
        "abcdefghijklm",
        "abcdefghijklmn",
        "abcdefghijklmno",
        "0123456789abcdef",
        "0123456789abcdeg",
        "0123456789abcdef" ++ "x",
        "0123456789abcdef" ++ "y",
        "0123456789abcdef" ++ "GHIJKLMNOPQRSTUV" ++ "WXYZabcdefghijkl" ++ "mnopqrstuvwxyzAB" ++ "CDEFGHIJKLMNOPQR",
        "0123456789abcdef" ++ "GHIJKLMNOPQRSTUV" ++ "WXYZabcdefghijkl" ++ "mnopqrstuvwxyzAB" ++ "cDEFGHIJKLMNOPQR",
        "src/chunked_string.zig",
        "src/chunk_pool.zig",
        "src/contants.zig",
        "build.zig",
        "z",
        "src/worktree/snapshot.zig",
        "src/worktree/scanner.zig",
    };

    for (test_paths, 0..) |path_a, i| {
        for (test_paths, 0..) |path_b, j| {
            var cs_a = store.put(path_a, 0, gpa);
            defer store.free(&cs_a, gpa);
            var cs_b = store.put(path_b, 0, gpa);
            defer store.free(&cs_b, gpa);

            const expected = std.mem.order(u8, path_a, path_b);
            const actual = cs_a.cmp(cs_b);

            if (actual != expected) {
                std.debug.print(
                    "cmp mismatch at ({d},\"{s}\") vs ({d},\"{s}\"): expected {}, got {}\n",
                    .{ i, path_a, j, path_b, expected, actual },
                );
            }
            try testing.expectEqual(expected, actual);
        }
    }
}

test "basename writes filename into buffer" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    const path = "src/worktree/snapshot.zig";
    const filename_offset: u32 = @intCast(std.mem.lastIndexOfScalar(u8, path, '/').? + 1);

    var cs = store.put(path, filename_offset, gpa);
    defer store.free(&cs, gpa);

    var buf: [64]u8 = undefined;
    const basename = cs.basename(&buf);
    try testing.expectEqual(@as(usize, path.len - filename_offset), basename.len);
    try testing.expectEqualSlices(u8, "snapshot.zig", basename);
}

test "basename spans chunk boundary" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    // 80 bytes = 5 chunks. Place filename_offset at 48 (start of chunk 3).
    const path = "0123456789abcdef" ++ "GHIJKLMNOPQRSTUV" ++ "WXYZabcdefghijkl" ++ "mnopqrstuvwxyzAB" ++ "CDEFGHIJKLMNOPQR";
    const filename_offset: u32 = 48;
    const expected = path[filename_offset..];

    var cs = store.put(path, filename_offset, gpa);
    defer store.free(&cs, gpa);

    var buf: [64]u8 = undefined;
    const basename = cs.basename(&buf);
    try testing.expectEqual(@as(usize, expected.len), basename.len);
    try testing.expectEqualSlices(u8, expected, basename);
}
