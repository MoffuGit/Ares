const std = @import("std");
const mem = std.mem;
const debug = std.debug;
const assert = debug.assert;
const Allocator = mem.Allocator;
const testing = std.testing;
const panic = debug.panic;
const atomic = std.atomic;
const builtin = @import("builtin");
const math = std.math;

const constans = @import("constants.zig");
const MAX_ALIGN = constans.MAX_ALIGN;

const log = std.log.scoped(.chunk_pool);

const Chunk = opaque {
    pub const Index = enum(u32) {
        none = math.maxInt(u32),
        _,
    };

    const Header = struct {
        next: u32,

        fn loadNext(self: *Header) Index {
            return @enumFromInt(@atomicLoad(u32, &self.next, .acquire));
        }

        fn storeNext(self: *Header, value: Index) void {
            @atomicStore(u32, &self.next, @intFromEnum(value), .release);
        }
    };

    fn header(self: *Chunk) *Header {
        return @ptrCast(@alignCast(self));
    }
};

fn packFreeList(version: u32, index: Chunk.Index) u64 {
    return (@as(u64, version) << 32) | @as(u64, @intFromEnum(index));
}

fn freeListIndex(state: u64) Chunk.Index {
    return @enumFromInt(@as(u32, @truncate(state)));
}

fn freeListVersion(state: u64) u32 {
    return @intCast(state >> 32);
}

pub const ChunkPool = struct {
    pub const Index = Chunk.Index;

    buffer: []u8,
    alignment: mem.Alignment,
    chunk_size: u32,
    reserved: atomic.Value(u32) = .init(0),
    free_list: atomic.Value(u64) = .init(packFreeList(0, .none)),

    pub fn init(self: *ChunkPool, allocator: Allocator, capacity: u32, size: u32) !void {
        assert(capacity < math.maxInt(u32));
        assert(size >= MAX_ALIGN.toByteUnits());
        assert(capacity > 0);
        assert(size > 0);

        const alignment: mem.Alignment = .fromByteUnits(size);
        const len = @as(usize, size) * @as(usize, capacity);
        const buffer = (allocator.rawAlloc(
            len,
            alignment,
            @returnAddress(),
        ) orelse return error.OutOfMemory)[0..len];

        log.debug("ChunkPool size={} capacity={} | Chunk size={}", .{ buffer.len, capacity, size });

        self.* = .{
            .buffer = buffer,
            .alignment = alignment,
            .chunk_size = size,
        };
    }

    pub fn deinit(self: *ChunkPool, gpa: Allocator) void {
        gpa.rawFree(self.buffer, self.alignment, @returnAddress());
    }

    fn popFreeList(self: *ChunkPool) ?Index {
        while (true) {
            const state = self.free_list.load(.acquire);
            const head_index = freeListIndex(state);
            if (head_index == .none) return null;
            const chunk = self.get(head_index);
            const next_index = chunk.?.header().loadNext();
            const new_state = packFreeList(freeListVersion(state) + 1, next_index);
            if (self.free_list.cmpxchgWeak(state, new_state, .acq_rel, .monotonic) == null) {
                return head_index;
            }
        }
    }

    fn allocBump(self: *ChunkPool) ?Index {
        while (true) {
            const current = self.reserved.load(.monotonic);
            const offset = @as(usize, current) * self.chunk_size;
            if (offset >= self.buffer.len) return null;
            if (self.reserved.cmpxchgWeak(current, current + 1, .monotonic, .monotonic) == null) {
                return @enumFromInt(current);
            }
        }
    }

    pub fn allocIndex(self: *ChunkPool) ?Index {
        return self.popFreeList() orelse self.allocBump();
    }

    pub fn sliceFromIndex(self: *ChunkPool, index: Index) ?[]u8 {
        if (index == .none) return null;
        const start = @as(usize, @intFromEnum(index)) * self.chunk_size;
        if (start >= self.buffer.len) return null;
        return self.buffer[start .. start + self.chunk_size];
    }

    pub fn alloc(self: *ChunkPool) ?[]u8 {
        const index = self.allocIndex() orelse return null;
        return self.sliceFromIndex(index).?;
    }

    pub fn freeIndex(self: *ChunkPool, index: Index) void {
        assert(index != .none);
        const chunk = self.get(index) orelse @panic("ChunkPool.freeIndex: index out of range");
        self.pushFreeList(index, chunk);
    }

    fn freePrepare(self: *ChunkPool, buffer: []u8) struct { index: Chunk.Index, chunk: *Chunk } {
        assert(buffer.len == self.chunk_size);
        assert(@intFromPtr(buffer.ptr) >= @intFromPtr(self.buffer.ptr));
        assert(@intFromPtr(buffer.ptr) + buffer.len <= @intFromPtr(self.buffer.ptr) + self.buffer.len);

        const offset = @intFromPtr(buffer.ptr) - @intFromPtr(self.buffer.ptr);
        assert(offset % self.chunk_size == 0);
        const index: Chunk.Index = @enumFromInt(offset / self.chunk_size);

        const chunk: *Chunk = @ptrCast(@alignCast(buffer.ptr));
        return .{ .index = index, .chunk = chunk };
    }

    pub fn free(self: *ChunkPool, buffer: []u8) void {
        const entry = self.freePrepare(buffer);
        self.pushFreeList(entry.index, entry.chunk);
    }

    fn pushFreeList(self: *ChunkPool, index: Chunk.Index, chunk: *Chunk) void {
        while (true) {
            const state = self.free_list.load(.acquire);
            const head_index = freeListIndex(state);
            chunk.header().storeNext(head_index);
            const new_state = packFreeList(freeListVersion(state) + 1, index);
            if (self.free_list.cmpxchgWeak(state, new_state, .acq_rel, .monotonic) == null) {
                return;
            }
        }
    }

    fn get(self: *ChunkPool, index: Chunk.Index) ?*Chunk {
        if (index == .none) return null;
        const start = @as(usize, @intFromEnum(index)) * self.chunk_size;
        return @ptrCast(@alignCast(&self.buffer[start]));
    }
};

pub const ChunkAllocator = struct {
    pools: []ChunkPool,

    const PoolConfig = struct { u32, u32 };

    fn lessThan(_: void, lhs: PoolConfig, rhs: PoolConfig) bool {
        return lhs.@"1" < rhs.@"1";
    }

    pub fn init(self: *ChunkAllocator, child_alloc: Allocator, pool_configs: []const PoolConfig) !void {
        self.* = .{
            .pools = undefined,
        };

        self.pools = try child_alloc.alloc(ChunkPool, pool_configs.len);
        errdefer child_alloc.free(self.pools);

        var initialized: usize = 0;
        errdefer {
            for (self.pools[0..initialized]) |*pool| pool.deinit(child_alloc);
        }

        var buffer: [100]PoolConfig = undefined;
        for (pool_configs, 0..) |config, index| {
            buffer[index] = .{ config.@"0", math.ceilPowerOfTwoAssert(u32, config.@"1") };
        }

        const ordered_pools = buffer[0..pool_configs.len];
        mem.sortUnstable(PoolConfig, buffer[0..pool_configs.len], {}, lessThan);

        var last: u32 = 0;
        for (ordered_pools, 0..) |config, index| {
            assert(last != config.@"1");

            try self.pools[index].init(child_alloc, config.@"0", config.@"1");

            last = config.@"1";
            initialized += 1;
        }
    }

    pub fn deinit(self: *ChunkAllocator, child_alloc: Allocator) void {
        for (self.pools) |*pool| pool.deinit(child_alloc);
        child_alloc.free(self.pools);
    }

    pub fn allocator(self: *ChunkAllocator) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = Allocator.noResize,
                .remap = Allocator.noRemap,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: mem.Alignment, _: usize) ?[*]u8 {
        const self: *ChunkAllocator = @ptrCast(@alignCast(ctx));
        const max_size = self.pools[self.pools.len - 1].chunk_size;
        if (len > max_size) panic("Chunk of {} bytes exceeds max chunk size {}", .{ len, max_size });

        for (self.pools) |*pool| {
            if (len > pool.chunk_size) continue;
            if (alignment.toByteUnits() > pool.alignment.toByteUnits()) continue;
            const buffer = pool.alloc() orelse return null;
            if (builtin.mode == .Debug and !builtin.is_test) {
                if (len < buffer.len >> 1) {
                    log.warn("Mostly unused chunk size={} used={}", .{ buffer.len, len });
                }
            }
            return buffer.ptr;
        }

        std.debug.assert(false);
        return null;
    }

    fn free(ctx: *anyopaque, memory: []u8, _: mem.Alignment, _: usize) void {
        const self: *ChunkAllocator = @ptrCast(@alignCast(ctx));

        for (self.pools) |*pool| {
            if (@intFromPtr(memory.ptr) < @intFromPtr(pool.buffer.ptr)) continue;
            if (@intFromPtr(memory.ptr) >= @intFromPtr(pool.buffer.ptr) + pool.buffer.len) continue;
            pool.free(memory.ptr[0..pool.chunk_size]);
            return;
        }

        std.debug.assert(false);
    }
};

test "Simple Chunk Pool" {
    const gpa = testing.allocator;

    var pool: ChunkPool = undefined;
    try pool.init(gpa, 2, 128);
    defer pool.deinit(gpa);

    const first = pool.alloc() orelse return error.TestUnexpectedResult;
    const second = pool.alloc() orelse return error.TestUnexpectedResult;
    try testing.expect(first.ptr != second.ptr);

    pool.free(first);

    const allocated = pool.alloc() orelse return error.TestUnexpectedResult;
    try testing.expectEqual(first.ptr, allocated.ptr);
    try testing.expectEqual(@as(usize, 128), allocated.len);
    try testing.expect(pool.alloc() == null);
}

test "Chunk Pool reuses chunk after capacity is exhausted" {
    const gpa = testing.allocator;

    var pool: ChunkPool = undefined;
    try pool.init(gpa, 3, 128);
    defer pool.deinit(gpa);

    const first = pool.alloc() orelse return error.TestUnexpectedResult;
    _ = pool.alloc() orelse return error.TestUnexpectedResult;
    _ = pool.alloc() orelse return error.TestUnexpectedResult;

    try testing.expect(pool.alloc() == null);

    pool.free(first);

    const reused = pool.alloc() orelse return error.TestUnexpectedResult;
    try testing.expectEqual(first.ptr, reused.ptr);
}

test "Chunk Pool index API allocates distinct writable indices" {
    const gpa = testing.allocator;

    var pool: ChunkPool = undefined;
    try pool.init(gpa, 3, 128);
    defer pool.deinit(gpa);

    const idx_a = pool.allocIndex() orelse return error.TestUnexpectedResult;
    const idx_b = pool.allocIndex() orelse return error.TestUnexpectedResult;
    try testing.expect(idx_a != .none);
    try testing.expect(idx_b != .none);
    try testing.expect(idx_a != idx_b);

    const slice_a = pool.sliceFromIndex(idx_a).?;
    const slice_b = pool.sliceFromIndex(idx_b).?;
    try testing.expectEqual(@as(usize, 128), slice_a.len);
    try testing.expect(slice_a.ptr != slice_b.ptr);

    @memset(slice_a, 0xAB);
    try testing.expectEqual(@as(u8, 0xAB), pool.sliceFromIndex(idx_a).?[0]);
    // Writing through one index must not bleed into another.
    try testing.expectEqual(@as(u8, 0), pool.sliceFromIndex(idx_b).?[0]);
}

test "Chunk Pool freeIndex then allocIndex reuses the slot" {
    const gpa = testing.allocator;

    var pool: ChunkPool = undefined;
    try pool.init(gpa, 2, 128);
    defer pool.deinit(gpa);

    const idx_a = pool.allocIndex() orelse return error.TestUnexpectedResult;
    _ = pool.allocIndex() orelse return error.TestUnexpectedResult;
    try testing.expect(pool.allocIndex() == null);

    pool.freeIndex(idx_a);

    const reused = pool.allocIndex() orelse return error.TestUnexpectedResult;
    try testing.expectEqual(idx_a, reused);
}

test "Chunk Pool sliceFromIndex rejects none and out-of-range indices" {
    const gpa = testing.allocator;

    var pool: ChunkPool = undefined;
    try pool.init(gpa, 2, 128);
    defer pool.deinit(gpa);

    try testing.expect(pool.sliceFromIndex(.none) == null);

    const forged: ChunkPool.Index = @enumFromInt(1_000_000);
    try testing.expect(pool.sliceFromIndex(forged) == null);
}

test "Chunk Allocator" {
    const gpa = testing.allocator;

    const Small = struct {
        a: u32,
        b: u32,
    };
    const Medium = struct {
        bytes: [80]u8,
    };

    var chunk_allocator: ChunkAllocator = undefined;
    try chunk_allocator.init(gpa, &.{ .{ 1, 64 }, .{ 1, 128 } });
    defer chunk_allocator.deinit(gpa);

    const alloc = chunk_allocator.allocator();
    const small = try alloc.create(Small);
    small.* = .{ .a = 1, .b = 2 };
    try testing.expectEqual(@as(u32, 1), small.a);
    try testing.expectError(error.OutOfMemory, alloc.create(Small));

    const medium = try alloc.create(Medium);
    try testing.expectError(error.OutOfMemory, alloc.create(Medium));

    alloc.destroy(small);

    const reused = try alloc.create(Small);
    try testing.expectEqual(small, reused);
    alloc.destroy(reused);
    alloc.destroy(medium);
}

test "Chunk Allocator orders chunk sizes from smallest to biggest" {
    const gpa = testing.allocator;

    var chunk_allocator: ChunkAllocator = undefined;
    try chunk_allocator.init(gpa, &.{ .{ 1, 128 }, .{ 1, 64 }, .{ 1, 256 } });
    defer chunk_allocator.deinit(gpa);

    try testing.expectEqual(@as(u32, 64), chunk_allocator.pools[0].chunk_size);
    try testing.expectEqual(@as(u32, 128), chunk_allocator.pools[1].chunk_size);
    try testing.expectEqual(@as(u32, 256), chunk_allocator.pools[2].chunk_size);
}
