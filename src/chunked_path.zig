const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const testing = std.testing;
const Io = std.Io;
const math = std.math;

const datastruct = @import("datastruct.zig");
const chunk_pool = @import("chunk_pool.zig");
const ChunkPool = chunk_pool.ChunkPool;
const mem_map = datastruct.mem_map;
const MemMap = mem_map.MemMap;
const MemMapRng = mem_map.MemMapRng;
const constans = @import("contants.zig");
const SIMD_CHUNK_BYTES = constans.SIMD_CHUNK_BYTES;
const MAX_PATH_LEN = constans.MAX_PATH_LEN;

pub const RANGE_NODE_SIZE = @sizeOf(MemMapRng);

pub const Chunk = [SIMD_CHUNK_BYTES]u8;

pub const ChunkedPathStore = @This();

io: Io,
mutex: Io.Mutex,
pool: ChunkPool,
dedup: std.AutoHashMap(Chunk, *Chunk),

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

    var memmap: MemMap = .{};
    var offset: usize = 0;
    while (offset < path.len) {
        var canonical: Chunk = [_]u8{0} ** SIMD_CHUNK_BYTES;
        const end = @min(offset + SIMD_CHUNK_BYTES, path.len);
        const chunk_len = end - offset;

        @memcpy(canonical[0..chunk_len], path[offset..end]);

        const chunk_ptr = self.internChunk(canonical);
        memmap.push(.{ .min = offset, .max = end }, chunk_ptr, alloc) catch @panic("MemMap Range Overflow");

        offset = end;
    }

    return .{
        .len = @intCast(path.len),
        .filename_offset = filename_offset,
        .memmap = memmap,
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
    assert(new_len <= MAX_PATH_LEN);
    const new_offset = len + filename_offset;

    @memcpy(buffer[len..new_len], suffix);

    return self.put(buffer[0..new_len], new_offset, alloc);
}

fn internChunk(self: *ChunkedPathStore, canonical: Chunk) *Chunk {
    self.lock();
    defer self.unlock();

    if (self.dedup.get(canonical)) |ptr| return ptr;

    const buf = self.pool.alloc() orelse @panic("SIMD CHUNK Overflow");
    const chunk: *Chunk = @ptrCast(@alignCast(buf.ptr));
    chunk.* = canonical;

    self.dedup.putAssumeCapacity(canonical, chunk);

    return chunk;
}

pub const ChunkedPath = struct {
    len: u32,
    filename_offset: u32,
    memmap: MemMap,

    pub fn path(self: *const ChunkedPath, buffer: []u8) []u8 {
        assert(buffer.len >= self.len);

        const read = self.memmap.read(.{ .min = 0, .max = self.len }, buffer);
        assert(read == self.len);

        return buffer[0..self.len];
    }

    pub fn basename(self: *const ChunkedPath, buffer: []u8) []u8 {
        const name_len: usize = self.len - self.filename_offset;
        assert(buffer.len >= name_len);

        const read = self.memmap.read(.{ .min = self.filename_offset, .max = self.len }, buffer[0..name_len]);
        assert(read == name_len);

        return buffer[0..name_len];
    }

    pub fn slice(self: *const ChunkedPath, allocator: Allocator) ![]u8 {
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

        var node_a = self.memmap.ranges.head;
        var node_b = other.memmap.ranges.head;
        var remaining_a: u32 = self.len;
        var remaining_b: u32 = other.len;

        while (remaining_a > 0 and remaining_b > 0) {
            const base_a = node_a.?.base;
            const base_b = node_b.?.base;

            // Deduped chunks share the same canonical pointer — skip the load.
            if (base_a != base_b) {
                const chunk_a: *Chunk = @ptrCast(@alignCast(base_a));
                const chunk_b: *Chunk = @ptrCast(@alignCast(base_b));

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
            }

            remaining_a -= @min(remaining_a, SIMD_CHUNK_BYTES);
            remaining_b -= @min(remaining_b, SIMD_CHUNK_BYTES);
            node_a = node_a.?.next;
            node_b = node_b.?.next;
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

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const node_alloc = arena.allocator();

    const path = "0123456789abcdef";
    const cs = store.put(path, 0, node_alloc);

    const bytes = try cs.slice(gpa);
    defer gpa.free(bytes);
    try testing.expectEqualSlices(u8, path, bytes);
}

test "multi-chunk path" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const node_alloc = arena.allocator();

    const path = "0123456789abcdef" ++ "GHIJKLMNOPQRSTUV" ++ "WXYZabcdefghijkl" ++ "mnopqrstuvwxyzAB";
    try testing.expectEqual(@as(usize, 64), path.len);

    const cs = store.put(path, 0, node_alloc);

    const bytes = try cs.slice(gpa);
    defer gpa.free(bytes);
    try testing.expectEqualSlices(u8, path, bytes);
}

test "multi-node path spans multiple ranges" {
    const gpa = testing.allocator;
    const io = testing.io;

    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 64);
    defer store.deinit(gpa);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const node_alloc = arena.allocator();

    const path = "0123456789abcdef" ++ "GHIJKLMNOPQRSTUV" ++ "WXYZabcdefghijkl" ++ "mnopqrstuvwxyzAB" ++ "CDEFGHIJKLMNOPQR";
    try testing.expectEqual(@as(usize, 80), path.len);

    const cs = store.put(path, 0, node_alloc);

    try testing.expectEqual(@as(u32, 80), cs.len);

    var count: usize = 0;
    var node = cs.memmap.ranges.head;
    while (node) |n| : (node = n.next) count += 1;
    try testing.expectEqual(@as(usize, 5), count);

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

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const node_alloc = arena.allocator();

    var path_buf: [MAX_PATH_LEN]u8 = undefined;
    for (&path_buf, 0..) |*b, i| b.* = @intCast(i % 256);
    const path = path_buf[0..];

    const cs = store.put(path, 0, node_alloc);

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

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const node_alloc = arena.allocator();

    const shared_prefix = "0123456789abcdef";
    const cs_a = store.put(shared_prefix, 0, node_alloc);
    const cs_b = store.put(shared_prefix, 0, node_alloc);

    try testing.expectEqual(cs_a.memmap.ranges.head.?.base, cs_b.memmap.ranges.head.?.base);
    try testing.expectEqual(@as(usize, 1), store.chunkCount());
}

test "filename offset preserved" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const node_alloc = arena.allocator();

    const path = "src/chunked_string.zig";
    const filename_offset: u32 = @intCast(std.mem.lastIndexOfScalar(u8, path, '/') orelse 0);

    const cs = store.put(path, filename_offset + 1, node_alloc);

    try testing.expectEqual(filename_offset + 1, cs.filename_offset);

    const bytes = try cs.slice(gpa);
    defer gpa.free(bytes);
    try testing.expectEqualSlices(u8, path, bytes);
    try testing.expectEqualSlices(u8, "chunked_string.zig", bytes[cs.filename_offset..]);
}

test "append short suffix to short path (merges into one chunk)" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const node_alloc = arena.allocator();

    const orig = "hello";
    const cs = store.put(orig, 0, node_alloc);

    const suffix = "/world";
    // filename_offset is relative to the suffix: "world" starts at index 1.
    const appended = store.append(cs, suffix, 1, node_alloc);

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

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const node_alloc = arena.allocator();

    const orig = "0123456789abcdef"; // exactly 16 bytes
    const cs = store.put(orig, 0, node_alloc);

    // "foo" starts at index 1 within the suffix "/foo".
    const appended = store.append(cs, "/foo", 1, node_alloc);

    try testing.expectEqual(@as(u32, 20), appended.len);
    const new_bytes = try appended.slice(gpa);
    defer gpa.free(new_bytes);
    try testing.expectEqualSlices(u8, "0123456789abcdef/foo", new_bytes);

    // The full chunk should be shared between the two paths.
    try testing.expectEqual(cs.memmap.ranges.head.?.base, appended.memmap.ranges.head.?.base);
}

test "append spanning multiple nodes" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const node_alloc = arena.allocator();

    // 80 bytes = 5 chunks = 2 nodes.
    const orig = "0123456789abcdef" ++ "GHIJKLMNOPQRSTUV" ++ "WXYZabcdefghijkl" ++ "mnopqrstuvwxyzAB" ++ "CDEFGHIJKLMNOPQR";
    const cs = store.put(orig, 0, node_alloc);

    const suffix = "/subdir/file.zig";
    const expected = orig ++ suffix;
    // "subdir/file.zig" starts at index 1 within the suffix.
    const appended = store.append(cs, suffix, 1, node_alloc);

    try testing.expectEqual(@as(u32, @intCast(expected.len)), appended.len);
    const new_bytes = try appended.slice(gpa);
    defer gpa.free(new_bytes);
    try testing.expectEqualSlices(u8, expected, new_bytes);

    // First 4 full chunks should be shared.
    var a_node = cs.memmap.ranges.head;
    var b_node = appended.memmap.ranges.head;
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        try testing.expectEqual(a_node.?.base, b_node.?.base);
        a_node = a_node.?.next;
        b_node = b_node.?.next;
    }
}

test "append that fills the partial chunk exactly" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const node_alloc = arena.allocator();

    // 10 bytes -> partial chunk with 10/16 used, 6 bytes of padding.
    const orig = "0123456789";
    const cs = store.put(orig, 0, node_alloc);

    // Suffix of 6 bytes fills the remainder exactly.
    const suffix = "abcdef";
    // filename starts at index 0 within the suffix.
    const appended = store.append(cs, suffix, 0, node_alloc);

    try testing.expectEqual(@as(u32, 16), appended.len);
    const new_bytes = try appended.slice(gpa);
    defer gpa.free(new_bytes);
    try testing.expectEqualSlices(u8, "0123456789abcdef", new_bytes);

    // The merged chunk should be a new canonical chunk (different from orig's partial).
    try testing.expect(cs.memmap.ranges.head.?.base != appended.memmap.ranges.head.?.base);
}

test "append resolves suffix-relative filename_offset to absolute" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const node_alloc = arena.allocator();

    // existing = "src/core" (8 bytes, filename "core" at offset 4)
    const orig = "src/core";
    const cs = store.put(orig, 4, node_alloc);

    // suffix = "/module/file.zig" — filename "file.zig" starts at index 8
    // within the suffix (after "/module/").
    const suffix = "/module/file.zig";
    const appended = store.append(cs, suffix, 8, node_alloc);

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

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const node_alloc = arena.allocator();

    const path = "src/chunked_string.zig";
    const cs_a = store.put(path, 0, node_alloc);
    const cs_b = store.put(path, 0, node_alloc);

    try testing.expectEqual(std.math.Order.eq, cs_a.cmp(cs_b));
    try testing.expectEqual(std.math.Order.eq, cs_b.cmp(cs_a));
}

test "cmp differs at first byte" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const node_alloc = arena.allocator();

    const cs_a = store.put("abc", 0, node_alloc);
    const cs_b = store.put("xbc", 0, node_alloc);

    try testing.expectEqual(std.math.Order.lt, cs_a.cmp(cs_b));
    try testing.expectEqual(std.math.Order.gt, cs_b.cmp(cs_a));
}

test "cmp differs at last byte of first chunk" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const node_alloc = arena.allocator();

    const path_a = "0123456789abcdeA";
    const path_b = "0123456789abcdeB";
    const cs_a = store.put(path_a, 0, node_alloc);
    const cs_b = store.put(path_b, 0, node_alloc);

    try testing.expectEqual(std.math.Order.lt, cs_a.cmp(cs_b));
    try testing.expectEqual(std.math.Order.gt, cs_b.cmp(cs_a));
}

test "cmp differs in second chunk" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const node_alloc = arena.allocator();

    // 32 bytes = 2 chunks. Second chunk differs at first byte.
    const path_a = "0123456789abcdef" ++ "ABCDEFGHIJKLMNOP";
    const path_b = "0123456789abcdef" ++ "aBCDEFGHIJKLMNOP";
    const cs_a = store.put(path_a, 0, node_alloc);
    const cs_b = store.put(path_b, 0, node_alloc);

    try testing.expectEqual(std.math.Order.lt, cs_a.cmp(cs_b)); // 'A' (0x41) < 'a' (0x61)
    try testing.expectEqual(std.math.Order.gt, cs_b.cmp(cs_a));
}

test "cmp differs in second node (multi-node)" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const node_alloc = arena.allocator();

    // 80 bytes = 5 chunks = 2 nodes. Difference at chunk 4 (first slot of second node).
    const base = "0123456789abcdef" ++ "GHIJKLMNOPQRSTUV" ++ "WXYZabcdefghijkl" ++ "mnopqrstuvwxyzAB";
    const path_a = base ++ "CDEFGHIJKLMNOPQR";
    const path_b = base ++ "cDEFGHIJKLMNOPQR";
    const cs_a = store.put(path_a, 0, node_alloc);
    const cs_b = store.put(path_b, 0, node_alloc);

    try testing.expectEqual(std.math.Order.lt, cs_a.cmp(cs_b)); // 'C' (0x43) < 'c' (0x63)
    try testing.expectEqual(std.math.Order.gt, cs_b.cmp(cs_a));
}

test "cmp prefix — shorter is less" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const node_alloc = arena.allocator();

    const cs_short = store.put("hello", 0, node_alloc);
    const cs_long = store.put("hello world", 0, node_alloc);

    try testing.expectEqual(std.math.Order.lt, cs_short.cmp(cs_long));
    try testing.expectEqual(std.math.Order.gt, cs_long.cmp(cs_short));
}

test "cmp prefix across chunk boundary" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const node_alloc = arena.allocator();

    // 16 bytes exactly vs 17 bytes (first chunk identical, second has 1 byte).
    const first_chunk = "0123456789abcdef";
    const cs_16 = store.put(first_chunk, 0, node_alloc);
    const cs_17 = store.put(first_chunk ++ "x", 0, node_alloc);

    try testing.expectEqual(std.math.Order.lt, cs_16.cmp(cs_17));
    try testing.expectEqual(std.math.Order.gt, cs_17.cmp(cs_16));
}

test "cmp partial chunk vs full chunk (padding as zero)" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const node_alloc = arena.allocator();

    // "hello" is 5 bytes + 11 zeros in its chunk.
    // "hello\x00world!!!!!" is 16 bytes (contains a real null at index 5).
    // The first chunk has 'w' at index 6 where "hello" has 0 (padding).
    // 0 < 'w', so "hello" < "hello\x00world!!!!!".
    const path_with_null = "hello\x00world!!!!!";
    try testing.expectEqual(@as(usize, 16), path_with_null.len);

    const cs_short = store.put("hello", 0, node_alloc);
    const cs_full = store.put(path_with_null, 0, node_alloc);

    try testing.expectEqual(std.math.Order.lt, cs_short.cmp(cs_full));
    try testing.expectEqual(std.math.Order.gt, cs_full.cmp(cs_short));
}

test "cmp long equal paths (multi-node)" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 16);
    defer store.deinit(gpa);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const node_alloc = arena.allocator();

    const path = "0123456789abcdef" ++ "GHIJKLMNOPQRSTUV" ++ "WXYZabcdefghijkl" ++ "mnopqrstuvwxyzAB" ++ "CDEFGHIJKLMNOPQR";
    const cs_a = store.put(path, 0, node_alloc);
    const cs_b = store.put(path, 0, node_alloc);

    try testing.expectEqual(std.math.Order.eq, cs_a.cmp(cs_b));
}

test "cmp max length equal" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 256);
    defer store.deinit(gpa);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const node_alloc = arena.allocator();

    var path_buf: [MAX_PATH_LEN]u8 = undefined;
    for (&path_buf, 0..) |*b, i| b.* = @intCast(i % 256);

    const cs_a = store.put(path_buf[0..], 0, node_alloc);
    const cs_b = store.put(path_buf[0..], 0, node_alloc);

    try testing.expectEqual(std.math.Order.eq, cs_a.cmp(cs_b));
}

test "cmp max length differ at last byte" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 256);
    defer store.deinit(gpa);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const node_alloc = arena.allocator();

    var path_a: [MAX_PATH_LEN]u8 = undefined;
    var path_b: [MAX_PATH_LEN]u8 = undefined;
    for (&path_a, &path_b, 0..) |*a, *b, i| {
        a.* = @intCast(i % 256);
        b.* = @intCast(i % 256);
    }
    path_a[MAX_PATH_LEN - 1] = 0;
    path_b[MAX_PATH_LEN - 1] = 1;

    const cs_a = store.put(path_a[0..], 0, node_alloc);
    const cs_b = store.put(path_b[0..], 0, node_alloc);

    try testing.expectEqual(std.math.Order.lt, cs_a.cmp(cs_b));
    try testing.expectEqual(std.math.Order.gt, cs_b.cmp(cs_a));
}

test "cmp matches std.mem.order on random paths" {
    const gpa = testing.allocator;
    const io = testing.io;
    var store: ChunkedPathStore = undefined;
    try store.init(io, gpa, 1024);
    defer store.deinit(gpa);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const node_alloc = arena.allocator();

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
            const cs_a = store.put(path_a, 0, node_alloc);
            const cs_b = store.put(path_b, 0, node_alloc);

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

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const node_alloc = arena.allocator();

    const path = "src/worktree/snapshot.zig";
    const filename_offset: u32 = @intCast(std.mem.lastIndexOfScalar(u8, path, '/').? + 1);

    const cs = store.put(path, filename_offset, node_alloc);

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

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const node_alloc = arena.allocator();

    // 80 bytes = 5 chunks. Place filename_offset at 48 (start of chunk 3).
    const path = "0123456789abcdef" ++ "GHIJKLMNOPQRSTUV" ++ "WXYZabcdefghijkl" ++ "mnopqrstuvwxyzAB" ++ "CDEFGHIJKLMNOPQR";
    const filename_offset: u32 = 48;
    const expected = path[filename_offset..];

    const cs = store.put(path, filename_offset, node_alloc);

    var buf: [64]u8 = undefined;
    const basename = cs.basename(&buf);
    try testing.expectEqual(@as(usize, expected.len), basename.len);
    try testing.expectEqualSlices(u8, expected, basename);
}
