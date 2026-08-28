const std = @import("std");
const Allocator = std.mem.Allocator;
const heap = std.heap;

const chunk_pool = @import("../chunk_pool.zig");
const ChunkPool = chunk_pool.ChunkPool;
const datastruct = @import("../datastruct.zig");
const SinglyLinkedList = datastruct.SinglyLinkedList;

const page_size = std.heap.pageSize();

pub const SwapChain = datastruct.SwapChain(FrameState, 3);

pub const FrameState = @This();

swap_chain: *SwapChain,
arena: heap.ArenaAllocator,
uniforms: Uniforms,
rect_list: BufferList,

pub fn init(self: *FrameState, swap_chain: *SwapChain, gpa: Allocator) !void {
    self.* = .{
        .arena = .init(gpa),
        .uniforms = undefined,
        .swap_chain = swap_chain,
        .rect_list = .{
            .count = 0,
            .nodes = .empty,
        },
    };
}

// pub fn rect(self: *FrameState, data: Rect) !void {
//     const arena = self.arena.allocator();
//     const list = self.rect_list;
//
//     if (list.nodes.is_empty()) {
//         const node = try arena.create(BufferNode);
//         try node.init(256, @sizeOf(Rect), arena);
//         list.push(node);
//     }
// }

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

    pub fn init(self: *BufferNode, capacity: u32, chunk_size: u32, arena: Allocator) !void {
        self.* = .{
            .next = null,
            .buffer = undefined,
        };

        try self.buffer.init(arena, capacity, chunk_size, .fromByteUnits(page_size));
    }
};

const BufferList = struct {
    const empty: BufferList = .{
        .nodes = .{},
        .count = 0,
    };
    nodes: SinglyLinkedList(BufferNode),
    count: u64,

    pub fn push(self: *BufferList, node: *BufferNode) void {
        self.nodes.append(node);
        self.count += 1;
    }
};
