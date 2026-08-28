const std = @import("std");
const Allocator = std.mem.Allocator;
const heap = std.heap;
const assert = std.debug.assert;
const testing = std.testing;

const chunk_pool = @import("../chunk_pool.zig");
const ChunkPool = chunk_pool.ChunkPool;
const datastruct = @import("../datastruct.zig");
const SinglyLinkedList = datastruct.SinglyLinkedList;

const page_size = std.heap.pageSize();

pub const SwapChain = datastruct.SwapChain(FrameState, 3);

pub const FrameState = @This();

swap_chain: *SwapChain,
arena: heap.ArenaAllocator,
rects: BufferList,
uniforms: *Uniforms,

pub fn init(self: *FrameState, swap_chain: *SwapChain, gpa: Allocator) !void {
    self.* = .{
        .arena = .init(gpa),
        .uniforms = undefined,
        .swap_chain = swap_chain,
        .rects = .empty,
    };
}

pub fn uniform(self: *FrameState, data: Uniforms) !void {
    const arena = self.arena.allocator();

    const buffer = arena.rawAlloc(@sizeOf(Uniforms), .fromByteUnits(page_size), @returnAddress()) orelse return error.OutOfMemory;
    const ptr: *Uniforms = @ptrCast(@alignCast(buffer));
    ptr.* = data;

    self.uniforms = ptr;
}

pub fn rect(self: *FrameState, data: Rect) !void {
    const arena = self.arena.allocator();
    const list = &self.rects;

    if (list.nodes.is_empty()) {
        const node = try arena.create(BufferNode);
        try node.init(.{
            .capacity = 256,
            .chunk_size = @sizeOf(Rect),
            .alignment = .fromByteUnits(page_size),
        }, arena);
        list.push(node);
    }

    const buffer = ptr: {
        if (list.nodes.head.?.pool.alloc()) |ptr| break :ptr ptr;

        const node = try arena.create(BufferNode);
        try node.init(.{
            .capacity = 256,
            .chunk_size = @sizeOf(Rect),
            .alignment = .fromByteUnits(page_size),
        }, arena);
        list.push(node);

        break :ptr node.pool.alloc() orelse unreachable;
    };

    assert(buffer.len == @sizeOf(Rect));

    const ptr: *Rect = @ptrCast(@alignCast(buffer.ptr));
    ptr.* = data;
}

pub fn deinit(self: *FrameState) void {
    self.arena.deinit();
}

pub fn release(self: *FrameState) void {
    self.rects = .empty;
    self.uniforms = undefined;
    _ = self.arena.reset(.retain_capacity);
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

pub const BufferNode = struct {
    next: ?*BufferNode,
    pool: ChunkPool,

    pub fn init(self: *BufferNode, opt: chunk_pool.Options, arena: Allocator) !void {
        self.* = .{
            .next = null,
            .pool = undefined,
        };

        try self.pool.init(arena, opt);
    }
};

pub const BufferList = struct {
    const empty: BufferList = .{
        .nodes = .empty,
    };
    nodes: SinglyLinkedList(BufferNode),

    pub fn push(self: *BufferList, node: *BufferNode) void {
        self.nodes.append(node);
    }
};
