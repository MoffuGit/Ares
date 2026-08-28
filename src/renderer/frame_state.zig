const std = @import("std");
const Allocator = std.mem.Allocator;
const heap = std.heap;

const chunk_pool = @import("../chunk_pool.zig");
const ChunkPool = chunk_pool.ChunkPool;
const datastruct = @import("../datastruct.zig");
const SinglyLinkedList = datastruct.SinglyLinkedList;

pub const SwapChain = datastruct.SwapChain(FrameState, 3);

pub const FrameState = @This();

swap_chain: *SwapChain,
arena: heap.ArenaAllocator,
uniforms: Uniforms,
rect_buffer: RectBuffer,

pub fn init(self: *FrameState, swap_chain: *SwapChain, gpa: Allocator) !void {
    self.* = .{
        .arena = .init(gpa),
        .uniforms = undefined,
        .swap_chain = swap_chain,
        .rect_buffer = .{
            .buffers = .{
                .count = 0,
                .buffers = .empty,
            },
        },
    };
}

pub fn deinit(self: *FrameState) void {
    self.arena.deinit();
}

pub fn release(self: *FrameState) void {
    _ = self.arena.reset(.free_all);
    self.swap_chain.releaseFrame();
}

pub const Uniforms = extern struct {
    viewport_size: [2]f32 align(8),
};

pub const Rect = extern struct {
    position: [4]f32 align(16),
    color_0: [4]f32 align(16),
    color_1: [4]f32 align(16),
    color_2: [4]f32 align(16),
    color_3: [4]f32 align(16),
};

const BufferNode = struct {
    next: ?*BufferNode,
    buffer: ChunkPool,
};

const BufferList = struct {
    const empty: BufferList = .{
        .buffers = .{},
        .count = 0,
    };
    buffers: SinglyLinkedList(BufferNode),
    count: u64,
};

const RectBuffer = struct {
    buffers: BufferList,
};
