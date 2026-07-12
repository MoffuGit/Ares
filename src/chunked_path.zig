const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const testing = std.testing;
const math = std.math;

const chunk_pool = @import("chunk_pool.zig");
const ChunkAllocator = chunk_pool.ChunkAllocator;
const constans = @import("contants.zig");
const SIMD_CHUNK_BYTES = constans.SIMD_CHUNK_BYTES;
const INLINE_CHUNKS = constans.INLINE_CHUNKS;
const MAX_PATH_LEN = constans.MAX_PATH_LEN;

pub const SIMD_CHUNK = [SIMD_CHUNK_BYTES]u8;

pub const InlineChunks = struct {
    next: ?*InlineChunks,
    chunks: [INLINE_CHUNKS]*SIMD_CHUNK,
};

const INLINE_NODE_SIZE = @sizeOf(InlineChunks);

pub const ChunkedPath = struct {
    len: u32,
    filename_offset: u32,
    head: ?*InlineChunks,

    pub const Iterator = struct {
        node: ?*InlineChunks,
        slot: usize,
        remaining: u32,

        pub fn next(self: *Iterator) ?[]const u8 {
            if (self.remaining == 0) return null;

            const node = self.node orelse return null;

            const chunk = node.chunks[self.slot];

            if (self.remaining >= SIMD_CHUNK_BYTES) {
                const result: []const u8 = chunk[0..SIMD_CHUNK_BYTES];

                self.remaining -= SIMD_CHUNK_BYTES;
                self.slot += 1;

                if (self.slot >= INLINE_CHUNKS) {
                    self.slot = 0;
                    self.node = node.next;
                }

                return result;
            } else {
                const result: []const u8 = chunk[0..self.remaining];

                self.remaining = 0;

                return result;
            }
        }
    };

    pub fn iterator(self: ChunkedPath) Iterator {
        return .{
            .node = self.head,
            .slot = 0,
            .remaining = self.len,
        };
    }

    pub fn write(self: ChunkedPath, buffer: []u8) usize {
        const to_copy = @min(self.len, buffer.len);

        var it = self.iterator();
        var offset: usize = 0;
        var remaining: usize = to_copy;

        while (it.next()) |segment| {
            if (remaining == 0) break;
            const take = @min(segment.len, remaining);
            @memcpy(buffer[offset .. offset + take], segment[0..take]);
            offset += take;
            remaining -= take;
        }

        return to_copy;
    }

    pub fn toSlice(self: ChunkedPath, allocator: Allocator) ![]u8 {
        const buf = try allocator.alloc(u8, self.len);
        assert(buf.len == self.write(buf));

        return buf;
    }

    pub fn cmp(self: ChunkedPath, other: ChunkedPath) math.Order {
        if (self.len == 0 and other.len == 0) return .eq;
        if (self.len == 0) return .lt;
        if (other.len == 0) return .gt;

        const Vec = @Vector(SIMD_CHUNK_BYTES, u8);
        const MaskInt = std.meta.Int(.unsigned, SIMD_CHUNK_BYTES);
        const all_ones: MaskInt = @as(MaskInt, 0) -% 1;

        var node_a = self.head;
        var node_b = other.head;
        var slot_a: usize = 0;
        var slot_b: usize = 0;
        var remaining_a: u32 = self.len;
        var remaining_b: u32 = other.len;

        while (remaining_a > 0 and remaining_b > 0) {
            const chunk_a: *SIMD_CHUNK = node_a.?.chunks[slot_a];
            const chunk_b: *SIMD_CHUNK = node_b.?.chunks[slot_b];

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

const SharedChunk = struct {
    ptr: *SIMD_CHUNK,
    ref_count: usize,
};

pub const ChunkedPathStore = struct {
    alloc: Allocator,
    chunks: ChunkAllocator,
    dedup: std.AutoHashMap(SIMD_CHUNK, SharedChunk),

    pub const Config = struct {
        chunk_capacity: u32,
        inline_capacity: u32,
    };

    pub fn init(self: *ChunkedPathStore, allocator: Allocator, config: Config) !void {
        self.* = .{
            .alloc = undefined,
            .chunks = undefined,
            .dedup = undefined,
        };

        try self.chunks.init(allocator, &.{
            .{ config.chunk_capacity, SIMD_CHUNK_BYTES },
            .{ config.inline_capacity, INLINE_NODE_SIZE },
        });
        errdefer self.chunks.deinit(allocator);

        self.alloc = self.chunks.allocator();

        self.dedup = .init(allocator);
        errdefer self.dedup.deinit();

        try self.dedup.ensureTotalCapacity(config.chunk_capacity);
    }

    pub fn deinit(self: *ChunkedPathStore, allocator: Allocator) void {
        self.dedup.deinit();
        self.chunks.deinit(allocator);
    }

    pub fn chunkCount(self: *const ChunkedPathStore) usize {
        return self.dedup.count();
    }

    pub fn put(self: *ChunkedPathStore, path: []const u8, filename_offset: u32) ChunkedPath {
        assert(path.len <= MAX_PATH_LEN);
        assert(filename_offset < path.len);
        assert(path.len > 0);

        const total_chunks = (path.len + SIMD_CHUNK_BYTES - 1) / SIMD_CHUNK_BYTES;
        const total_nodes = (total_chunks + INLINE_CHUNKS - 1) / INLINE_CHUNKS;

        var head: ?*InlineChunks = null;
        var tail: ?*InlineChunks = null;
        {
            var i: usize = 0;

            while (i < total_nodes) : (i += 1) {
                const node = self.alloc.create(InlineChunks) catch
                    @panic("Inline Chunks Overflow");

                node.* = .{ .next = null, .chunks = undefined };

                if (head == null) head = node else tail.?.next = node;

                tail = node;
            }
        }

        var cur_node = head;
        var slot: usize = 0;
        var chunks_interned: usize = 0;

        var offset: usize = 0;

        while (offset < path.len) {
            var canonical: SIMD_CHUNK = [_]u8{0} ** SIMD_CHUNK_BYTES;
            const end = @min(offset + SIMD_CHUNK_BYTES, path.len);
            const chunk_len = end - offset;

            @memcpy(canonical[0..chunk_len], path[offset..end]);

            const chunk_ptr = self.internChunk(canonical);

            cur_node.?.chunks[slot] = chunk_ptr;
            chunks_interned += 1;
            slot += 1;

            if (slot >= INLINE_CHUNKS) {
                slot = 0;
                cur_node = cur_node.?.next;
            }

            offset = end;
        }

        return .{
            .len = @intCast(path.len),
            .filename_offset = filename_offset,
            .head = head,
        };
    }

    pub fn append(
        self: *ChunkedPathStore,
        existing: ChunkedPath,
        suffix: []const u8,
        filename_offset: u32,
    ) ChunkedPath {
        assert(existing.len > 0);
        assert(suffix.len > 0);

        const suffix_len: u32 = @intCast(suffix.len);
        const new_len: u32 = existing.len + suffix_len;

        assert(new_len <= MAX_PATH_LEN);
        assert(filename_offset < suffix_len);

        const resolved_offset: u32 = existing.len + filename_offset;

        const full_chunks = existing.len / SIMD_CHUNK_BYTES;
        const remainder = existing.len % SIMD_CHUNK_BYTES;

        var tail_buf: [MAX_PATH_LEN]u8 = undefined;
        var tail_len: usize = 0;

        if (remainder > 0) {
            var ex_node = existing.head;
            var ex_slot: usize = 0;
            var i: usize = 0;
            while (i < full_chunks) : (i += 1) {
                ex_slot += 1;
                if (ex_slot >= INLINE_CHUNKS) {
                    ex_slot = 0;
                    ex_node = ex_node.?.next;
                }
            }
            const last_chunk = ex_node.?.chunks[ex_slot];
            @memcpy(tail_buf[0..remainder], last_chunk[0..remainder]);
            tail_len = remainder;
        }
        @memcpy(tail_buf[tail_len .. tail_len + suffix.len], suffix);
        tail_len += suffix.len;

        const tail_chunks = (tail_len + SIMD_CHUNK_BYTES - 1) / SIMD_CHUNK_BYTES;
        const new_total_chunks = full_chunks + tail_chunks;
        const new_total_nodes = (new_total_chunks + INLINE_CHUNKS - 1) / INLINE_CHUNKS;

        var head: ?*InlineChunks = null;
        var tail_node: ?*InlineChunks = null;
        {
            var i: usize = 0;
            while (i < new_total_nodes) : (i += 1) {
                const node = self.alloc.create(InlineChunks) catch
                    @panic("Inline Chunks Overflow");
                node.* = .{ .next = null, .chunks = undefined };
                if (head == null) head = node else tail_node.?.next = node;
                tail_node = node;
            }
        }

        var cur_node = head;
        var slot: usize = 0;
        {
            var ex_node = existing.head;
            var ex_slot: usize = 0;
            var i: usize = 0;
            while (i < full_chunks) : (i += 1) {
                const chunk_ptr = ex_node.?.chunks[ex_slot];
                cur_node.?.chunks[slot] = self.internChunk(chunk_ptr.*);
                slot += 1;
                if (slot >= INLINE_CHUNKS) {
                    slot = 0;
                    cur_node = cur_node.?.next;
                }
                ex_slot += 1;
                if (ex_slot >= INLINE_CHUNKS) {
                    ex_slot = 0;
                    ex_node = ex_node.?.next;
                }
            }
        }

        {
            var offset: usize = 0;
            while (offset < tail_len) {
                var canonical: SIMD_CHUNK = [_]u8{0} ** SIMD_CHUNK_BYTES;
                const end = @min(offset + SIMD_CHUNK_BYTES, tail_len);
                const chunk_len = end - offset;
                @memcpy(canonical[0..chunk_len], tail_buf[offset..end]);
                cur_node.?.chunks[slot] = self.internChunk(canonical);
                slot += 1;
                if (slot >= INLINE_CHUNKS) {
                    slot = 0;
                    cur_node = cur_node.?.next;
                }
                offset = end;
            }
        }

        return .{
            .len = new_len,
            .filename_offset = resolved_offset,
            .head = head,
        };
    }

    pub fn free(self: *ChunkedPathStore, chunked_path: *ChunkedPath) void {
        assert(chunked_path.len > 0);

        const total_chunks = (chunked_path.len + SIMD_CHUNK_BYTES - 1) / SIMD_CHUNK_BYTES;

        assert(total_chunks > 0);

        var node = chunked_path.head;
        var released: usize = 0;

        while (node) |n| {
            const next = n.next;
            const slots = @min(INLINE_CHUNKS, total_chunks - released);
            for (n.chunks[0..slots]) |chunk_ptr| {
                self.destroyChunk(chunk_ptr);
            }
            released += slots;
            self.alloc.destroy(n);
            node = next;
        }
    }

    fn internChunk(self: *ChunkedPathStore, canonical: SIMD_CHUNK) *SIMD_CHUNK {
        if (self.dedup.getPtr(canonical)) |entry| {
            entry.ref_count += 1;
            return entry.ptr;
        }

        const buf = self.alloc.create(SIMD_CHUNK) catch @panic("SIMD CHUNK Overflow");
        @memcpy(buf, &canonical);
        const ptr: *SIMD_CHUNK = @ptrCast(@alignCast(buf.ptr));

        self.dedup.putAssumeCapacity(canonical, .{ .ptr = ptr, .ref_count = 1 });

        return ptr;
    }

    fn destroyChunk(self: *ChunkedPathStore, ptr: *SIMD_CHUNK) void {
        const key: SIMD_CHUNK = ptr.*;
        const entry = self.dedup.getPtr(key) orelse return;
        assert(entry.ptr == ptr);

        if (entry.ref_count > 1) {
            entry.ref_count -= 1;
        } else {
            _ = self.dedup.remove(key);
            self.alloc.destroy(ptr);
        }
    }
};

test "short partial path round-trip" {
    const gpa = testing.allocator;
    var store: ChunkedPathStore = undefined;
    try store.init(gpa, .{ .chunk_capacity = 16, .inline_capacity = 16 });
    defer store.deinit(gpa);

    const path = "hello";
    var cs = store.put(path, 0);
    defer store.free(&cs);

    try testing.expectEqual(@as(u32, 5), cs.len);
    try testing.expect(cs.head != null);
    try testing.expectEqual(@as(?*InlineChunks, null), cs.head.?.next);

    const bytes = try cs.toSlice(gpa);
    defer gpa.free(bytes);
    try testing.expectEqualSlices(u8, path, bytes);

    var it = cs.iterator();
    const seg = it.next().?;
    try testing.expectEqual(@as(usize, 5), seg.len);
    try testing.expectEqualSlices(u8, "hello", seg);
    try testing.expectEqual(@as(?[]const u8, null), it.next());
}

test "exactly 16 bytes" {
    const gpa = testing.allocator;
    var store: ChunkedPathStore = undefined;
    try store.init(gpa, .{ .chunk_capacity = 16, .inline_capacity = 16 });
    defer store.deinit(gpa);

    const path = "0123456789abcdef";
    var cs = store.put(path, 0);
    defer store.free(&cs);

    try testing.expectEqual(@as(u32, 16), cs.len);
    try testing.expectEqual(@as(?*InlineChunks, null), cs.head.?.next);

    const bytes = try cs.toSlice(gpa);
    defer gpa.free(bytes);
    try testing.expectEqualSlices(u8, path, bytes);
}

test "exactly 64 bytes (one node, four chunks)" {
    const gpa = testing.allocator;
    var store: ChunkedPathStore = undefined;
    try store.init(gpa, .{ .chunk_capacity = 16, .inline_capacity = 16 });
    defer store.deinit(gpa);

    const path = "0123456789abcdef" ++ "GHIJKLMNOPQRSTUV" ++ "WXYZabcdefghijkl" ++ "mnopqrstuvwxyzAB";
    try testing.expectEqual(@as(usize, 64), path.len);

    var cs = store.put(path, 0);
    defer store.free(&cs);

    try testing.expectEqual(@as(u32, 64), cs.len);
    try testing.expectEqual(@as(?*InlineChunks, null), cs.head.?.next);

    const bytes = try cs.toSlice(gpa);
    defer gpa.free(bytes);
    try testing.expectEqualSlices(u8, path, bytes);
}

test "longer than 64 bytes (multi-node)" {
    const gpa = testing.allocator;

    var store: ChunkedPathStore = undefined;
    try store.init(gpa, .{ .chunk_capacity = 64, .inline_capacity = 64 });
    defer store.deinit(gpa);

    const path = "0123456789abcdef" ++ "GHIJKLMNOPQRSTUV" ++ "WXYZabcdefghijkl" ++ "mnopqrstuvwxyzAB" ++ "CDEFGHIJKLMNOPQR";
    try testing.expectEqual(@as(usize, 80), path.len);

    var cs = store.put(path, 0);
    defer store.free(&cs);

    try testing.expectEqual(@as(u32, 80), cs.len);
    try testing.expect(cs.head != null);
    try testing.expect(cs.head.?.next != null);
    try testing.expectEqual(@as(?*InlineChunks, null), cs.head.?.next.?.next);

    const bytes = try cs.toSlice(gpa);
    defer gpa.free(bytes);
    try testing.expectEqualSlices(u8, path, bytes);
}

test "maximum 4096-byte path" {
    const gpa = testing.allocator;
    var store: ChunkedPathStore = undefined;
    try store.init(gpa, .{ .chunk_capacity = 256, .inline_capacity = 64 });
    defer store.deinit(gpa);

    var path_buf: [MAX_PATH_LEN]u8 = undefined;
    for (&path_buf, 0..) |*b, i| b.* = @intCast(i % 256);
    const path = path_buf[0..];

    var cs = store.put(path, 0);
    defer store.free(&cs);

    try testing.expectEqual(@as(u32, MAX_PATH_LEN), cs.len);

    const bytes = try cs.toSlice(gpa);
    defer gpa.free(bytes);
    try testing.expectEqualSlices(u8, path, bytes);
}

test "identical chunks shared across paths" {
    const gpa = testing.allocator;
    var store: ChunkedPathStore = undefined;
    try store.init(gpa, .{ .chunk_capacity = 16, .inline_capacity = 16 });
    defer store.deinit(gpa);

    const shared_prefix = "0123456789abcdef";
    var cs_a = store.put(shared_prefix, 0);
    defer store.free(&cs_a);
    var cs_b = store.put(shared_prefix, 0);
    defer store.free(&cs_b);

    try testing.expectEqual(cs_a.head.?.chunks[0], cs_b.head.?.chunks[0]);
    try testing.expectEqual(@as(usize, 1), store.chunkCount());
}

test "repeated chunk within one path" {
    const gpa = testing.allocator;
    var store: ChunkedPathStore = undefined;
    try store.init(gpa, .{ .chunk_capacity = 1, .inline_capacity = 4 });
    defer store.deinit(gpa);

    const block = "AAAAAAAAAAAAAAAA";
    const path = block ++ block;
    try testing.expectEqual(@as(usize, 32), path.len);

    var cs = store.put(path, 0);
    defer store.free(&cs);

    try testing.expectEqual(cs.head.?.chunks[0], cs.head.?.chunks[1]);
    try testing.expectEqual(@as(usize, 1), store.chunkCount());

    const bytes = try cs.toSlice(gpa);
    defer gpa.free(bytes);
    try testing.expectEqualSlices(u8, path, bytes);
}

test "different chunks are not shared" {
    const gpa = testing.allocator;
    var store: ChunkedPathStore = undefined;
    try store.init(gpa, .{ .chunk_capacity = 16, .inline_capacity = 16 });
    defer store.deinit(gpa);

    var cs_a = store.put("0123456789abcdef", 0);
    defer store.free(&cs_a);
    var cs_b = store.put("abcdefghijklmnop", 0);
    defer store.free(&cs_b);

    try testing.expect(cs_a.head.?.chunks[0] != cs_b.head.?.chunks[0]);
    try testing.expectEqual(@as(usize, 2), store.chunkCount());
}

test "filename offset preserved" {
    const gpa = testing.allocator;
    var store: ChunkedPathStore = undefined;
    try store.init(gpa, .{ .chunk_capacity = 16, .inline_capacity = 16 });
    defer store.deinit(gpa);

    const path = "src/chunked_string.zig";
    const filename_offset: u32 = @intCast(std.mem.lastIndexOfScalar(u8, path, '/') orelse 0);

    var cs = store.put(path, filename_offset + 1);
    defer store.free(&cs);

    try testing.expectEqual(filename_offset + 1, cs.filename_offset);

    const bytes = try cs.toSlice(gpa);
    defer gpa.free(bytes);
    try testing.expectEqualSlices(u8, path, bytes);
    try testing.expectEqualSlices(u8, "chunked_string.zig", bytes[cs.filename_offset..]);
}

test "identical bytes with different offsets still share chunks" {
    const gpa = testing.allocator;
    var store: ChunkedPathStore = undefined;
    try store.init(gpa, .{ .chunk_capacity = 16, .inline_capacity = 16 });
    defer store.deinit(gpa);

    const path = "0123456789abcdef";
    var cs_a = store.put(path, 0);
    defer store.free(&cs_a);
    var cs_b = store.put(path, 5);
    defer store.free(&cs_b);

    try testing.expectEqual(cs_a.head.?.chunks[0], cs_b.head.?.chunks[0]);
    try testing.expectEqual(@as(u32, 0), cs_a.filename_offset);
    try testing.expectEqual(@as(u32, 5), cs_b.filename_offset);
}

test "store bulk deinit no leak" {
    const gpa = testing.allocator;
    var store: ChunkedPathStore = undefined;
    try store.init(gpa, .{ .chunk_capacity = 64, .inline_capacity = 64 });
    defer store.deinit(gpa);

    _ = store.put("src/chunked_string.zig", 4);
    _ = store.put("src/contants.zig", 4);
    _ = store.put("src/chunk_pool.zig", 4);
    _ = store.put("build.zig", 0);
    _ = store.put("src/worktree/snapshot.zig", 4);
}

test "copyTo with exact and undersized buffers" {
    const gpa = testing.allocator;
    var store: ChunkedPathStore = undefined;
    try store.init(gpa, .{ .chunk_capacity = 16, .inline_capacity = 16 });
    defer store.deinit(gpa);

    const path = "0123456789abcdefGHIJKLMNOPQRSTUV";
    var cs = store.put(path, 0);
    defer store.free(&cs);

    var exact: [32]u8 = undefined;
    const copied_exact = cs.write(&exact);
    try testing.expectEqual(@as(usize, 32), copied_exact);
    try testing.expectEqualSlices(u8, path, exact[0..copied_exact]);

    var large: [64]u8 = undefined;
    const copied_large = cs.write(&large);
    try testing.expectEqual(@as(usize, 32), copied_large);
    try testing.expectEqualSlices(u8, path, large[0..copied_large]);

    var small: [16]u8 = undefined;
    const copied_small = cs.write(&small);
    try testing.expectEqual(@as(usize, 16), copied_small);
    try testing.expectEqualSlices(u8, path[0..16], small[0..copied_small]);
}

test "iterator over multi-node path" {
    const gpa = testing.allocator;
    var store: ChunkedPathStore = undefined;
    try store.init(gpa, .{ .chunk_capacity = 64, .inline_capacity = 64 });
    defer store.deinit(gpa);

    const path = "0123456789abcdef" ++ "GHIJKLMNOPQRSTUV" ++ "WXYZabcdefghijkl" ++ "mnopqrstuvwxyzAB" ++ "CDEFGHIJKLMNOPQR";
    var cs = store.put(path, 0);
    defer store.free(&cs);

    var it = cs.iterator();
    var offset: usize = 0;
    while (it.next()) |seg| {
        try testing.expectEqualSlices(u8, path[offset .. offset + seg.len], seg);
        offset += seg.len;
    }
    try testing.expectEqual(@as(usize, 80), offset);
}

test "append short suffix to short path (merges into one chunk)" {
    const gpa = testing.allocator;
    var store: ChunkedPathStore = undefined;
    try store.init(gpa, .{ .chunk_capacity = 64, .inline_capacity = 64 });
    defer store.deinit(gpa);

    const orig = "hello";
    var cs = store.put(orig, 0);
    defer store.free(&cs);

    const suffix = "/world";
    // filename_offset is relative to the suffix: "world" starts at index 1.
    var appended = store.append(cs, suffix, 1);
    defer store.free(&appended);

    // Original is unchanged.
    try testing.expectEqual(@as(u32, 5), cs.len);
    const orig_bytes = try cs.toSlice(gpa);
    defer gpa.free(orig_bytes);
    try testing.expectEqualSlices(u8, orig, orig_bytes);

    // Appended path has the combined content.
    try testing.expectEqual(@as(u32, 11), appended.len);
    try testing.expectEqual(@as(u32, 6), appended.filename_offset);
    const new_bytes = try appended.toSlice(gpa);
    defer gpa.free(new_bytes);
    try testing.expectEqualSlices(u8, "hello/world", new_bytes);
}

test "append to exact-chunk-boundary path (suffix starts new chunk)" {
    const gpa = testing.allocator;
    var store: ChunkedPathStore = undefined;
    try store.init(gpa, .{ .chunk_capacity = 64, .inline_capacity = 64 });
    defer store.deinit(gpa);

    const orig = "0123456789abcdef"; // exactly 16 bytes
    var cs = store.put(orig, 0);
    defer store.free(&cs);

    // "foo" starts at index 1 within the suffix "/foo".
    var appended = store.append(cs, "/foo", 1);
    defer store.free(&appended);

    try testing.expectEqual(@as(u32, 20), appended.len);
    const new_bytes = try appended.toSlice(gpa);
    defer gpa.free(new_bytes);
    try testing.expectEqualSlices(u8, "0123456789abcdef/foo", new_bytes);

    // The full chunk should be shared between the two paths.
    try testing.expectEqual(cs.head.?.chunks[0], appended.head.?.chunks[0]);
}

test "append spanning multiple nodes" {
    const gpa = testing.allocator;
    var store: ChunkedPathStore = undefined;
    try store.init(gpa, .{ .chunk_capacity = 256, .inline_capacity = 64 });
    defer store.deinit(gpa);

    // 80 bytes = 5 chunks = 2 nodes.
    const orig = "0123456789abcdef" ++ "GHIJKLMNOPQRSTUV" ++ "WXYZabcdefghijkl" ++ "mnopqrstuvwxyzAB" ++ "CDEFGHIJKLMNOPQR";
    var cs = store.put(orig, 0);
    defer store.free(&cs);

    const suffix = "/subdir/file.zig";
    const expected = orig ++ suffix;
    // "subdir/file.zig" starts at index 1 within the suffix.
    var appended = store.append(cs, suffix, 1);
    defer store.free(&appended);

    try testing.expectEqual(@as(u32, @intCast(expected.len)), appended.len);
    const new_bytes = try appended.toSlice(gpa);
    defer gpa.free(new_bytes);
    try testing.expectEqualSlices(u8, expected, new_bytes);

    // First 4 full chunks (first node) should be shared.
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        try testing.expectEqual(cs.head.?.chunks[i], appended.head.?.chunks[i]);
    }
}

test "append that fills the partial chunk exactly" {
    const gpa = testing.allocator;
    var store: ChunkedPathStore = undefined;
    try store.init(gpa, .{ .chunk_capacity = 64, .inline_capacity = 64 });
    defer store.deinit(gpa);

    // 10 bytes -> partial chunk with 10/16 used, 6 bytes of padding.
    const orig = "0123456789";
    var cs = store.put(orig, 0);
    defer store.free(&cs);

    // Suffix of 6 bytes fills the remainder exactly.
    const suffix = "abcdef";
    // filename starts at index 0 within the suffix.
    var appended = store.append(cs, suffix, 0);
    defer store.free(&appended);

    try testing.expectEqual(@as(u32, 16), appended.len);
    const new_bytes = try appended.toSlice(gpa);
    defer gpa.free(new_bytes);
    try testing.expectEqualSlices(u8, "0123456789abcdef", new_bytes);

    // The merged chunk should be a new canonical chunk (different from orig's partial).
    try testing.expect(cs.head.?.chunks[0] != appended.head.?.chunks[0]);
}

test "append preserves original after original is freed" {
    const gpa = testing.allocator;
    var store: ChunkedPathStore = undefined;
    try store.init(gpa, .{ .chunk_capacity = 256, .inline_capacity = 64 });
    defer store.deinit(gpa);

    const orig = "0123456789abcdef"; // full 16-byte chunk
    var cs = store.put(orig, 0);

    // "test" starts at index 1 within the suffix "/test".
    var appended = store.append(cs, "/test", 1);
    defer store.free(&appended);

    // Free the original; the appended path's shared chunk should still be valid.
    store.free(&cs);

    const new_bytes = try appended.toSlice(gpa);
    defer gpa.free(new_bytes);
    try testing.expectEqualSlices(u8, "0123456789abcdef/test", new_bytes);
}

test "append resolves suffix-relative filename_offset to absolute" {
    const gpa = testing.allocator;
    var store: ChunkedPathStore = undefined;
    try store.init(gpa, .{ .chunk_capacity = 64, .inline_capacity = 64 });
    defer store.deinit(gpa);

    // existing = "src/core" (8 bytes, filename "core" at offset 4)
    const orig = "src/core";
    var cs = store.put(orig, 4);
    defer store.free(&cs);

    // suffix = "/module/file.zig" — filename "file.zig" starts at index 8
    // within the suffix (after "/module/").
    const suffix = "/module/file.zig";
    var appended = store.append(cs, suffix, 8);
    defer store.free(&appended);

    // Resolved offset should be 8 (existing.len) + 8 = 16.
    try testing.expectEqual(@as(u32, 16), appended.filename_offset);

    const bytes = try appended.toSlice(gpa);
    defer gpa.free(bytes);
    try testing.expectEqualSlices(u8, "src/core/module/file.zig", bytes);
    try testing.expectEqualSlices(u8, "file.zig", bytes[appended.filename_offset..]);
}

// -- cmp tests --

test "cmp equal strings" {
    const gpa = testing.allocator;
    var store: ChunkedPathStore = undefined;
    try store.init(gpa, .{ .chunk_capacity = 64, .inline_capacity = 64 });
    defer store.deinit(gpa);

    const path = "src/chunked_string.zig";
    var cs_a = store.put(path, 0);
    defer store.free(&cs_a);
    var cs_b = store.put(path, 0);
    defer store.free(&cs_b);

    try testing.expectEqual(std.math.Order.eq, cs_a.cmp(cs_b));
    try testing.expectEqual(std.math.Order.eq, cs_b.cmp(cs_a));
}

test "cmp differs at first byte" {
    const gpa = testing.allocator;
    var store: ChunkedPathStore = undefined;
    try store.init(gpa, .{ .chunk_capacity = 16, .inline_capacity = 16 });
    defer store.deinit(gpa);

    var cs_a = store.put("abc", 0);
    defer store.free(&cs_a);
    var cs_b = store.put("xbc", 0);
    defer store.free(&cs_b);

    try testing.expectEqual(std.math.Order.lt, cs_a.cmp(cs_b));
    try testing.expectEqual(std.math.Order.gt, cs_b.cmp(cs_a));
}

test "cmp differs at last byte of first chunk" {
    const gpa = testing.allocator;
    var store: ChunkedPathStore = undefined;
    try store.init(gpa, .{ .chunk_capacity = 16, .inline_capacity = 16 });
    defer store.deinit(gpa);

    const path_a = "0123456789abcdeA";
    const path_b = "0123456789abcdeB";
    var cs_a = store.put(path_a, 0);
    defer store.free(&cs_a);
    var cs_b = store.put(path_b, 0);
    defer store.free(&cs_b);

    try testing.expectEqual(std.math.Order.lt, cs_a.cmp(cs_b));
    try testing.expectEqual(std.math.Order.gt, cs_b.cmp(cs_a));
}

test "cmp differs in second chunk" {
    const gpa = testing.allocator;
    var store: ChunkedPathStore = undefined;
    try store.init(gpa, .{ .chunk_capacity = 64, .inline_capacity = 64 });
    defer store.deinit(gpa);

    // 32 bytes = 2 chunks. Second chunk differs at first byte.
    const path_a = "0123456789abcdef" ++ "ABCDEFGHIJKLMNOP";
    const path_b = "0123456789abcdef" ++ "aBCDEFGHIJKLMNOP";
    var cs_a = store.put(path_a, 0);
    defer store.free(&cs_a);
    var cs_b = store.put(path_b, 0);
    defer store.free(&cs_b);

    try testing.expectEqual(std.math.Order.lt, cs_a.cmp(cs_b)); // 'A' (0x41) < 'a' (0x61)
    try testing.expectEqual(std.math.Order.gt, cs_b.cmp(cs_a));
}

test "cmp differs in second node (multi-node)" {
    const gpa = testing.allocator;
    var store: ChunkedPathStore = undefined;
    try store.init(gpa, .{ .chunk_capacity = 64, .inline_capacity = 64 });
    defer store.deinit(gpa);

    // 80 bytes = 5 chunks = 2 nodes. Difference at chunk 4 (first slot of second node).
    const base = "0123456789abcdef" ++ "GHIJKLMNOPQRSTUV" ++ "WXYZabcdefghijkl" ++ "mnopqrstuvwxyzAB";
    const path_a = base ++ "CDEFGHIJKLMNOPQR";
    const path_b = base ++ "cDEFGHIJKLMNOPQR";
    var cs_a = store.put(path_a, 0);
    defer store.free(&cs_a);
    var cs_b = store.put(path_b, 0);
    defer store.free(&cs_b);

    try testing.expectEqual(std.math.Order.lt, cs_a.cmp(cs_b)); // 'C' (0x43) < 'c' (0x63)
    try testing.expectEqual(std.math.Order.gt, cs_b.cmp(cs_a));
}

test "cmp prefix — shorter is less" {
    const gpa = testing.allocator;
    var store: ChunkedPathStore = undefined;
    try store.init(gpa, .{ .chunk_capacity = 64, .inline_capacity = 64 });
    defer store.deinit(gpa);

    var cs_short = store.put("hello", 0);
    defer store.free(&cs_short);
    var cs_long = store.put("hello world", 0);
    defer store.free(&cs_long);

    try testing.expectEqual(std.math.Order.lt, cs_short.cmp(cs_long));
    try testing.expectEqual(std.math.Order.gt, cs_long.cmp(cs_short));
}

test "cmp prefix across chunk boundary" {
    const gpa = testing.allocator;
    var store: ChunkedPathStore = undefined;
    try store.init(gpa, .{ .chunk_capacity = 64, .inline_capacity = 64 });
    defer store.deinit(gpa);

    // 16 bytes exactly vs 17 bytes (first chunk identical, second has 1 byte).
    const first_chunk = "0123456789abcdef";
    var cs_16 = store.put(first_chunk, 0);
    defer store.free(&cs_16);
    var cs_17 = store.put(first_chunk ++ "x", 0);
    defer store.free(&cs_17);

    try testing.expectEqual(std.math.Order.lt, cs_16.cmp(cs_17));
    try testing.expectEqual(std.math.Order.gt, cs_17.cmp(cs_16));
}

test "cmp partial chunk vs full chunk (padding as zero)" {
    const gpa = testing.allocator;
    var store: ChunkedPathStore = undefined;
    try store.init(gpa, .{ .chunk_capacity = 64, .inline_capacity = 64 });
    defer store.deinit(gpa);

    // "hello" is 5 bytes + 11 zeros in its chunk.
    // "hello\x00world!!!!!" is 16 bytes (contains a real null at index 5).
    // The first chunk has 'w' at index 6 where "hello" has 0 (padding).
    // 0 < 'w', so "hello" < "hello\x00world!!!!!".
    const path_with_null = "hello\x00world!!!!!";
    try testing.expectEqual(@as(usize, 16), path_with_null.len);

    var cs_short = store.put("hello", 0);
    defer store.free(&cs_short);
    var cs_full = store.put(path_with_null, 0);
    defer store.free(&cs_full);

    try testing.expectEqual(std.math.Order.lt, cs_short.cmp(cs_full));
    try testing.expectEqual(std.math.Order.gt, cs_full.cmp(cs_short));
}

test "cmp long equal paths (multi-node)" {
    const gpa = testing.allocator;
    var store: ChunkedPathStore = undefined;
    try store.init(gpa, .{ .chunk_capacity = 256, .inline_capacity = 64 });
    defer store.deinit(gpa);

    const path = "0123456789abcdef" ++ "GHIJKLMNOPQRSTUV" ++ "WXYZabcdefghijkl" ++ "mnopqrstuvwxyzAB" ++ "CDEFGHIJKLMNOPQR";
    var cs_a = store.put(path, 0);
    defer store.free(&cs_a);
    var cs_b = store.put(path, 0);
    defer store.free(&cs_b);

    try testing.expectEqual(std.math.Order.eq, cs_a.cmp(cs_b));
}

test "cmp max length equal" {
    const gpa = testing.allocator;
    var store: ChunkedPathStore = undefined;
    try store.init(gpa, .{ .chunk_capacity = 256, .inline_capacity = 128 });
    defer store.deinit(gpa);

    var path_buf: [MAX_PATH_LEN]u8 = undefined;
    for (&path_buf, 0..) |*b, i| b.* = @intCast(i % 256);

    var cs_a = store.put(path_buf[0..], 0);
    defer store.free(&cs_a);
    var cs_b = store.put(path_buf[0..], 0);
    defer store.free(&cs_b);

    try testing.expectEqual(std.math.Order.eq, cs_a.cmp(cs_b));
}

test "cmp max length differ at last byte" {
    const gpa = testing.allocator;
    var store: ChunkedPathStore = undefined;
    try store.init(gpa, .{ .chunk_capacity = 256, .inline_capacity = 128 });
    defer store.deinit(gpa);

    var path_a: [MAX_PATH_LEN]u8 = undefined;
    var path_b: [MAX_PATH_LEN]u8 = undefined;
    for (&path_a, &path_b, 0..) |*a, *b, i| {
        a.* = @intCast(i % 256);
        b.* = @intCast(i % 256);
    }
    path_a[MAX_PATH_LEN - 1] = 0;
    path_b[MAX_PATH_LEN - 1] = 1;

    var cs_a = store.put(path_a[0..], 0);
    defer store.free(&cs_a);
    var cs_b = store.put(path_b[0..], 0);
    defer store.free(&cs_b);

    try testing.expectEqual(std.math.Order.lt, cs_a.cmp(cs_b));
    try testing.expectEqual(std.math.Order.gt, cs_b.cmp(cs_a));
}

test "cmp ignores filename_offset" {
    const gpa = testing.allocator;
    var store: ChunkedPathStore = undefined;
    try store.init(gpa, .{ .chunk_capacity = 16, .inline_capacity = 16 });
    defer store.deinit(gpa);

    const path = "0123456789abcdef";
    var cs_a = store.put(path, 0);
    defer store.free(&cs_a);
    var cs_b = store.put(path, 5);
    defer store.free(&cs_b);

    // Same path bytes, different filename_offset — cmp should still be .eq.
    try testing.expectEqual(std.math.Order.eq, cs_a.cmp(cs_b));
}

test "cmp matches std.mem.order on random paths" {
    const gpa = testing.allocator;
    var store: ChunkedPathStore = undefined;
    try store.init(gpa, .{ .chunk_capacity = 256, .inline_capacity = 64 });
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
            var cs_a = store.put(path_a, 0);
            defer store.free(&cs_a);
            var cs_b = store.put(path_b, 0);
            defer store.free(&cs_b);

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
