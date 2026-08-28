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
uniforms: Uniforms,
rect_list: BufferList,

pub fn init(self: *FrameState, swap_chain: *SwapChain, gpa: Allocator) !void {
    self.* = .{
        .arena = .init(gpa),
        .uniforms = undefined,
        .swap_chain = swap_chain,
        .rect_list = .empty,
    };
}

pub fn rect(self: *FrameState, data: Rect) !void {
    const arena = self.arena.allocator();
    const list = &self.rect_list;

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
        if (list.nodes.head.?.buffer.alloc()) |ptr| break :ptr ptr;

        const node = try arena.create(BufferNode);
        try node.init(.{
            .capacity = 256,
            .chunk_size = @sizeOf(Rect),
            .alignment = .fromByteUnits(page_size),
        }, arena);
        list.push(node);

        break :ptr node.buffer.alloc() orelse unreachable;
    };

    assert(buffer.len == @sizeOf(Rect));

    const ptr: *Rect = @ptrCast(@alignCast(buffer.ptr));
    ptr.* = data;
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

    pub fn init(self: *BufferNode, opt: chunk_pool.Options, arena: Allocator) !void {
        self.* = .{
            .next = null,
            .buffer = undefined,
        };

        try self.buffer.init(arena, opt);
    }
};

const BufferList = struct {
    const empty: BufferList = .{
        .nodes = .empty,
    };
    nodes: SinglyLinkedList(BufferNode),

    pub fn push(self: *BufferList, node: *BufferNode) void {
        self.nodes.append(node);
    }
};

test "Rect List" {
    const gpa = testing.allocator;
    var state: FrameState = undefined;
    try state.init(undefined, gpa);
    defer state.deinit();

    const data: Rect = .{
        .position = .{ 1, 1, 1, 1 },
        .color_0 = .{ 1, 1, 1, 1 },
        .color_1 = .{ 1, 1, 1, 1 },
        .color_2 = .{ 1, 1, 1, 1 },
        .color_3 = .{ 1, 1, 1, 1 },
    };
    try state.rect(data);

    try testing.expect(!state.rect_list.nodes.is_empty());
    const head = state.rect_list.nodes.head.?;
    try testing.expectEqual(1, head.buffer.reserved);
    const ptr: *Rect = @ptrCast(@alignCast(head.buffer.buffer[0..@sizeOf(Rect)]));
    try testing.expectEqual(data, ptr.*);
}
