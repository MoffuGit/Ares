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
const Io = std.Io;

const log = std.log.scoped(.chunk_pool);

const Index = enum(u32) {
    none = math.maxInt(u32),
    _,
};
const Chunk = opaque {
    const Header = struct {
        next: Index,
    };

    fn header(self: *Chunk) *Header {
        return @ptrCast(@alignCast(self));
    }
};

pub const ChunkPool = struct {
    buffer: []u8,
    alignment: mem.Alignment,
    chunk_size: u32,
    reserved: u32 = 0,
    free_list: Index = .none,
    mutex: Io.Mutex,

    pub fn init(self: *ChunkPool, allocator: Allocator, capacity: u32, chunk_size: u32, alignment: mem.Alignment) !void {
        assert(capacity < math.maxInt(u32));
        assert(capacity > 0);
        assert(chunk_size > 0);

        const len = @as(usize, chunk_size) * @as(usize, capacity);
        const buffer = (allocator.rawAlloc(
            len,
            alignment,
            @returnAddress(),
        ) orelse return error.OutOfMemory)[0..len];

        log.debug("Chunk Pool size={B} capacity={} size={}", .{ buffer.len, capacity, chunk_size });

        self.* = .{
            .buffer = buffer,
            .alignment = alignment,
            .chunk_size = chunk_size,
            .mutex = .init,
        };
    }

    pub fn alloc(self: *ChunkPool) ?[]u8 {
        if (self.free_list == .none) {
            const index = self.reserved;
            const offset = index * self.chunk_size;

            if (offset == self.buffer.len) return null;
            self.reserved += 1;

            return self.buffer[offset .. offset + self.chunk_size];
        } else {
            const index = self.free_list;

            const offset = @intFromEnum(index) * self.chunk_size;
            const chunk: *Chunk = @ptrCast(@alignCast(&self.buffer[offset]));
            const next = chunk.header().next;
            self.free_list = next;

            return self.buffer[offset .. offset + self.chunk_size];
        }
    }

    pub fn threadSafeAlloc(self: *ChunkPool, io: Io) ?[]u8 {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);

        return self.alloc();
    }

    pub fn free(self: *ChunkPool, buffer: []u8) void {
        assert(buffer.len == self.chunk_size);
        assert(@intFromPtr(buffer.ptr) >= @intFromPtr(self.buffer.ptr));
        assert(@intFromPtr(buffer.ptr) + buffer.len <= @intFromPtr(self.buffer.ptr) + self.buffer.len);

        const offset = @intFromPtr(buffer.ptr) - @intFromPtr(self.buffer.ptr);
        assert(offset % self.chunk_size == 0);
        const index: Index = @enumFromInt(offset / self.chunk_size);
        const chunk: *Chunk = @ptrCast(@alignCast(buffer.ptr));

        const head = self.free_list;
        chunk.header().next = head;

        self.free_list = index;
    }

    pub fn threadSafeFree(self: *ChunkPool, buffer: []u8, io: Io) void {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);

        self.free(buffer);
    }

    pub fn deinit(self: *ChunkPool, gpa: Allocator) void {
        gpa.rawFree(self.buffer, self.alignment, @returnAddress());
    }
};

pub const PoolConfig = struct { u32, u32 };

fn lessThan(_: void, lhs: PoolConfig, rhs: PoolConfig) bool {
    return lhs.@"1" < rhs.@"1";
}

pub const ChunkAllocator = struct {
    pools: []ChunkPool,
    io: Io,

    pub fn init(self: *ChunkAllocator, child_alloc: Allocator, pool_configs: []const PoolConfig) !void {
        self.* = .{
            .pools = undefined,
            .io = undefined,
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

            try self.pools[index].init(child_alloc, config.@"0", config.@"1", .fromByteUnits(config.@"1"));

            last = config.@"1";
            initialized += 1;
        }
    }

    pub fn initThreadSafe(self: *ChunkAllocator, child_alloc: Allocator, pool_configs: []const PoolConfig, io: Io) !void {
        try self.init(child_alloc, pool_configs);
        self.io = io;
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

    pub fn threadSafeAllocator(self: *ChunkAllocator) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = threadSafeAlloc,
                .resize = Allocator.noResize,
                .remap = Allocator.noRemap,
                .free = threadSafeFree,
            },
        };
    }

    fn findPool(self: *ChunkAllocator, len: usize, alignment: mem.Alignment) ?*ChunkPool {
        assert(self.pools[self.pools.len - 1].chunk_size >= len);

        for (self.pools) |*pool| {
            if (len > pool.chunk_size) continue;
            if (alignment.toByteUnits() > pool.alignment.toByteUnits()) continue;
            return pool;
        }

        return null;
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: mem.Alignment, _: usize) ?[*]u8 {
        const self: *ChunkAllocator = @ptrCast(@alignCast(ctx));
        const pool = self.findPool(len, alignment) orelse return null;
        const buffer = pool.alloc() orelse return null;

        if (builtin.mode == .Debug and !builtin.is_test and len < buffer.len >> 1) {
            log.warn("Unused chunk size={} used={}", .{ buffer.len, len });
        }

        return buffer.ptr;
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: mem.Alignment, _: usize) void {
        const self: *ChunkAllocator = @ptrCast(@alignCast(ctx));
        const pool = self.findPool(memory.len, alignment) orelse unreachable;
        pool.free(memory.ptr[0..pool.chunk_size]);
    }

    fn threadSafeAlloc(ctx: *anyopaque, len: usize, alignment: mem.Alignment, _: usize) ?[*]u8 {
        const self: *ChunkAllocator = @ptrCast(@alignCast(ctx));
        const pool = self.findPool(len, alignment) orelse return null;
        const buffer = pool.threadSafeAlloc(self.io) orelse return null;

        if (builtin.mode == .Debug and !builtin.is_test and len < buffer.len >> 1) {
            log.warn("Unused chunk size={} used={}", .{ buffer.len, len });
        }

        return buffer.ptr;
    }

    fn threadSafeFree(ctx: *anyopaque, memory: []u8, alignment: mem.Alignment, _: usize) void {
        const self: *ChunkAllocator = @ptrCast(@alignCast(ctx));
        const pool = self.findPool(memory.len, alignment) orelse unreachable;
        pool.threadSafeFree(memory.ptr[0..pool.chunk_size], self.io);
    }
};

test "Simple Chunk Pool" {
    const gpa = testing.allocator;

    var pool: ChunkPool = undefined;
    try pool.init(gpa, 2, 128, .fromByteUnits(128));
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
    try pool.init(gpa, 3, 128, .fromByteUnits(128));
    defer pool.deinit(gpa);

    const first = pool.alloc() orelse return error.TestUnexpectedResult;
    _ = pool.alloc() orelse return error.TestUnexpectedResult;
    _ = pool.alloc() orelse return error.TestUnexpectedResult;

    try testing.expect(pool.alloc() == null);

    pool.free(first);

    const reused = pool.alloc() orelse return error.TestUnexpectedResult;
    try testing.expectEqual(first.ptr, reused.ptr);
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
