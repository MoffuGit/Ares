const std = @import("std");
const mem = std.mem;
const debug = std.debug;
const assert = debug.assert;
const Allocator = mem.Allocator;
const testing = std.testing;

const constans = @import("contants.zig");
const MAX_ALIGN = constans.MAX_ALIGN;

const Chunk = opaque {
    pub const Index = enum(u32) {
        none = std.math.maxInt(u32),
        _,
    };

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
    free_list: Chunk.Index = .none,

    pub fn init(self: *ChunkPool, allocator: Allocator, capacity: u32, size: u32) !void {
        assert(capacity < std.math.maxInt(u32));
        assert(size >= MAX_ALIGN.toByteUnits());

        const alignment: mem.Alignment = .fromByteUnits(size);
        const len = @as(usize, size) * @as(usize, capacity);
        const buffe = (allocator.rawAlloc(
            len,
            alignment,
            @returnAddress(),
        ) orelse return error.OutOfMemory)[0..len];

        self.* = .{
            .buffer = buffe,
            .alignment = alignment,
            .chunk_size = size,
        };
    }

    pub fn deinit(self: *ChunkPool, gpa: Allocator) void {
        gpa.rawFree(self.buffer, self.alignment, @returnAddress());
    }

    pub fn alloc(self: *ChunkPool) ?[]u8 {
        const chunk = if (self.get(self.free_list)) |free_chunk| b: {
            self.free_list = free_chunk.header().next;
            break :b free_chunk;
        } else b: {
            const offset = @as(usize, self.reserved) * self.chunk_size;
            if (offset >= self.buffer.len) return null;
            self.reserved += 1;
            break :b @as(*Chunk, @ptrCast(@alignCast(&self.buffer[offset])));
        };

        const ptr: [*]u8 = @ptrCast(chunk);
        return ptr[0..self.chunk_size];
    }

    pub fn free(self: *ChunkPool, buffer: []u8) void {
        assert(buffer.len == self.chunk_size);
        assert(@intFromPtr(buffer.ptr) >= @intFromPtr(self.buffer.ptr));
        assert(@intFromPtr(buffer.ptr) + buffer.len <= @intFromPtr(self.buffer.ptr) + self.buffer.len);

        const offset = @intFromPtr(buffer.ptr) - @intFromPtr(self.buffer.ptr);
        assert(offset % self.chunk_size == 0);
        const index: Chunk.Index = @enumFromInt(offset / self.chunk_size);

        const chunk: *Chunk = @ptrCast(@alignCast(buffer.ptr));
        chunk.header().* = .{ .next = self.free_list };
        self.free_list = index;
    }

    fn get(self: *ChunkPool, index: Chunk.Index) ?*Chunk {
        if (index == .none) return null;
        const start = @as(usize, @intFromEnum(index)) * self.chunk_size;
        return @ptrCast(@alignCast(&self.buffer[start]));
    }
};

pub const ChunkAllocator = struct {
    pools: []ChunkPool,

    pub fn init(self: *ChunkAllocator, child_alloc: Allocator, capacity: u32, comptime sizes: anytype) !void {
        self.pools = try child_alloc.alloc(ChunkPool, sizes.len);
        errdefer child_alloc.free(self.pools);

        var initialized: usize = 0;
        errdefer {
            for (self.pools[0..initialized]) |*pool| pool.deinit(child_alloc);
        }

        inline for (sizes, 0..) |size, index| {
            try self.pools[index].init(child_alloc, capacity, std.math.ceilPowerOfTwoAssert(u32, size));
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

        for (self.pools) |*pool| {
            if (len > pool.chunk_size) continue;
            if (alignment.toByteUnits() > pool.alignment.toByteUnits()) continue;
            const buffer = pool.alloc() orelse return null;
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
    try chunk_allocator.init(gpa, 1, .{ 64, 128 });
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
