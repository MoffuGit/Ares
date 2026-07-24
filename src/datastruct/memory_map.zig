//SOURCE: https://github.com/EpicGames/raddebugger
//LICENSE: [RADDEBUGGER]

const std = @import("std");
const math = @import("../math.zig");
const queue = @import("queue.zig");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const MemoryMapRange = struct {
    vaddr_range: math.Rngu64,
    base: [*]u8,
};

const MemoryMapNode = struct {
    range: MemoryMapRange,
    next: ?*MemoryMapNode = null,
};

const MemoryMap = struct {
    nodes: queue.Queue(MemoryMapNode) = .{},

    pub fn push(self: *MemoryMap, range: math.Rngu64, base: *anyopaque, alloc: Allocator) !void {
        const node = try alloc.create(MemoryMapNode);
        node.* = .{ .range = .{ .base = @ptrCast(base), .vaddr_range = range } };

        self.nodes.push(node);
    }

    pub fn read(self: *MemoryMap, range: math.Rngu64, dest: []u8) u64 {
        var dest_vaddr = range.min;
        while (true) {
            var found = false;
            const start_vaddr = dest_vaddr;
            var node = self.nodes.head;
            while (node) |n| : (node = n.next) {
                if (n.range.vaddr_range.contains(dest_vaddr)) {
                    const src_off = dest_vaddr - n.range.vaddr_range.min;
                    const possible = n.range.vaddr_range.max - dest_vaddr;
                    const needed = range.max - dest_vaddr;
                    const to_read = @min(needed, possible);

                    const dest_off: usize = @intCast(dest_vaddr - range.min);
                    const len: usize = @intCast(to_read);
                    const off: usize = @intCast(src_off);
                    @memcpy(dest[dest_off .. dest_off + len], n.range.base[off .. off + len]);

                    dest_vaddr += to_read;
                    found = true;
                }
            }
            if (!found or dest_vaddr == start_vaddr) break;
        }

        return dest_vaddr - range.min;
    }

    pub fn slice(self: *MemoryMap, range: math.Rngu64, alloc: Allocator) ![]u8 {
        const buffer = try alloc.alloc(u8, range.dim());
        _ = self.read(range, buffer);
        return buffer;
    }
};

test "Memory Map Simple Test" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var map: MemoryMap = .{};

    var buffer: [16]u8 = .{5} ** 5 ++ .{0} ** 11;
    try map.push(.{ .min = 0, .max = buffer.len }, &buffer, arena.allocator());

    var new_buffer: [16]u8 = undefined;
    const readed = map.read(.{ .min = 0, .max = buffer.len }, &new_buffer);
    try testing.expectEqual(buffer.len, readed);
    try testing.expectEqual(buffer, new_buffer);
}

test "Memory Map Simple Slice Test" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var map: MemoryMap = .{};

    var buffer: [16]u8 = .{5} ** 5 ++ .{0} ** 11;
    try map.push(.{ .min = 0, .max = buffer.len }, &buffer, arena.allocator());

    const slice = try map.slice(.{ .min = 0, .max = buffer.len }, arena.allocator());

    try testing.expectEqualStrings(&buffer, slice);
}

test "Memory Map: small buffers read all at once" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var map: MemoryMap = .{};

    // Three 4-byte buffers at contiguous vaddr ranges.
    var buf_a: [4]u8 = .{ 0x10, 0x11, 0x12, 0x13 };
    var buf_b: [4]u8 = .{ 0x20, 0x21, 0x22, 0x23 };
    var buf_c: [4]u8 = .{ 0x30, 0x31, 0x32, 0x33 };
    try map.push(.{ .min = 0, .max = buf_a.len }, &buf_a, arena.allocator());
    try map.push(.{ .min = 4, .max = 4 + buf_b.len }, &buf_b, arena.allocator());
    try map.push(.{ .min = 8, .max = 8 + buf_c.len }, &buf_c, arena.allocator());

    var dest: [12]u8 = undefined;
    const readed = map.read(.{ .min = 0, .max = 12 }, &dest);
    try testing.expectEqual(12, readed);

    const expected: [12]u8 = .{
        0x10, 0x11, 0x12, 0x13,
        0x20, 0x21, 0x22, 0x23,
        0x30, 0x31, 0x32, 0x33,
    };
    try testing.expectEqual(expected, dest);
}

test "Memory Map: two medium buffers read into one chunk" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var map: MemoryMap = .{};

    // Two 64-byte buffers at contiguous vaddr ranges.
    // Each byte stores its own vaddr so verification is trivial.
    var buf_a: [64]u8 = undefined;
    var buf_b: [64]u8 = undefined;
    for (0..64) |i| buf_a[i] = @intCast(i);
    for (0..64) |i| buf_b[i] = @intCast(i + 64);

    try map.push(.{ .min = 0, .max = buf_a.len }, &buf_a, arena.allocator());
    try map.push(.{ .min = 64, .max = 64 + buf_b.len }, &buf_b, arena.allocator());

    var dest: [128]u8 = undefined;
    const readed = map.read(.{ .min = 0, .max = 128 }, &dest);
    try testing.expectEqual(128, readed);

    for (0..128) |i| try testing.expectEqual(@as(u8, @intCast(i)), dest[i]);
}

test "Memory Map: two medium buffers read in smaller chunks" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var map: MemoryMap = .{};

    var buf_a: [64]u8 = undefined;
    var buf_b: [64]u8 = undefined;
    for (0..64) |i| buf_a[i] = @intCast(i);
    for (0..64) |i| buf_b[i] = @intCast(i + 64);

    try map.push(.{ .min = 0, .max = buf_a.len }, &buf_a, arena.allocator());
    try map.push(.{ .min = 64, .max = 64 + buf_b.len }, &buf_b, arena.allocator());

    // Read in 32-byte chunks — some chunks straddle the two buffers.
    const chunk_size: u64 = 32;
    var offset: u64 = 0;
    while (offset < 128) : (offset += chunk_size) {
        var chunk: [32]u8 = undefined;
        const readed = map.read(.{ .min = offset, .max = offset + chunk_size }, &chunk);
        try testing.expectEqual(chunk_size, readed);

        for (0..chunk_size) |i| {
            try testing.expectEqual(@as(u8, @intCast(offset + i)), chunk[i]);
        }
    }
}

test "Memory Map: overlapping ranges, first inserted takes priority" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var map: MemoryMap = .{};

    // A covers 0-8 (first inserted, takes priority in the overlap).
    // B covers 0-16 (second inserted, overlaps A in 0-8, extends to 16).
    var buf_a: [8]u8 = .{0xAA} ** 8;
    var buf_b: [16]u8 = .{0xBB} ** 16;
    try map.push(.{ .min = 0, .max = buf_a.len }, &buf_a, arena.allocator());
    try map.push(.{ .min = 0, .max = buf_b.len }, &buf_b, arena.allocator());

    var dest: [16]u8 = undefined;
    const readed = map.read(.{ .min = 0, .max = 16 }, &dest);
    try testing.expectEqual(16, readed);

    // Overlap region 0-8 comes from A (priority), 8-16 comes from B.
    for (0..8) |i| try testing.expectEqual(@as(u8, 0xAA), dest[i]);
    for (8..16) |i| try testing.expectEqual(@as(u8, 0xBB), dest[i]);
}

test "Memory Map: gap stops the read at last valid byte" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    var map: MemoryMap = .{};

    // A covers 0-8, B covers 16-24. Gap from 8-16.
    var buf_a: [8]u8 = .{0xAA} ** 8;
    var buf_b: [8]u8 = .{0xBB} ** 8;
    try map.push(.{ .min = 0, .max = buf_a.len }, &buf_a, arena.allocator());
    try map.push(.{ .min = 16, .max = 16 + buf_b.len }, &buf_b, arena.allocator());

    var dest: [24]u8 = undefined;
    const readed = map.read(.{ .min = 0, .max = 24 }, &dest);
    // Read stops at the gap — only 8 bytes read.
    try testing.expectEqual(8, readed);

    for (0..8) |i| try testing.expectEqual(@as(u8, 0xAA), dest[i]);
}
