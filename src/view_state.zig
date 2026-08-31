const std = @import("std");
const Allocator = std.mem.Allocator;
const heap = std.heap;
const assert = std.debug.assert;
const testing = std.testing;

const App = @import("app.zig");
const WindowState = App.WindowState;
const chunk_pool = @import("chunk_pool.zig");
const datastruct = @import("datastruct.zig");
const DoublyLinkedList = datastruct.DoublyLinkedList;
const LinkedListCollection = datastruct.LinkedListCollection;

pub var curr_state: ?*ViewState = null;
pub var null_block: Block = .empty;

pub fn startBuild(window_state: *WindowState) !void {
    assert(curr_state == null);
    const state = &window_state.view_state;
    state.root = &null_block;
    state.stack = .empty;
    state.block_count = 0;

    curr_state = state;

    const root = try Block.new();
    state.root = root;

    try push(.ancestors, .{ .block = root });
}

pub fn endBuild() void {
    const state = curr_state orelse unreachable;
    state.frame += 1;
    _ = state.frame_arenas[state.frame % state.frame_arenas.len].reset(.retain_capacity);

    curr_state = null;
}

pub const ViewState = struct {
    arena: heap.ArenaAllocator,

    root: *Block,
    block_count: u64,
    frame: u64,
    frame_arenas: [2]heap.ArenaAllocator,
    stack: LinkedListCollection(StackNodes),

    chunks: chunk_pool.ChunkAllocator,

    pub fn init(self: *ViewState, gpa: Allocator) !void {
        self.* = .{
            .stack = .empty,
            .root = &null_block,
            .block_count = 0,
            .frame = 0,
            .frame_arenas = .{ .init(gpa), .init(gpa) },
            .arena = .init(gpa),
            .chunks = undefined,
        };

        const arena = self.arena.allocator();
        errdefer self.arena.deinit();

        try self.chunks.init(arena, &.{.{ .capacity = 2048, .chunk_size = @sizeOf(Block) }});
    }

    pub fn deinit(self: *ViewState) void {
        for (self.frame_arenas) |arena| arena.deinit();
        self.arena.deinit();
    }

    pub fn frameArena(self: *ViewState) Allocator {
        return self.frame_arenas[self.frame % self.frame_arenas.len].allocator();
    }
};

const Stacks = enum { ancestors, axis, color, width, height };

const StackNodes = union(Stacks) {
    ancestors: struct { next: ?*@This() = null, block: *Block },
    axis: struct { next: ?*@This() = null, axis: Axis },
    color: struct { next: ?*@This() = null, color: [4]f32 },
    width: struct { next: ?*@This() = null, size: Size },
    height: struct { next: ?*@This() = null, size: Size },
};

fn StackNode(comptime tag: std.meta.Tag(StackNodes)) type {
    return @FieldType(StackNodes, @tagName(tag));
}

pub fn push(comptime tag: std.meta.Tag(StackNodes), data: StackNode(tag)) !void {
    const state = curr_state orelse unreachable;

    const arena = state.frameArena();
    const node = try arena.create(StackNode(tag));
    node.* = data;
    state.stack.prepend(tag, node);
}

pub fn pop(comptime tag: std.meta.Tag(StackNodes)) ?*StackNode(tag) {
    const state = curr_state orelse unreachable;
    return state.stack.pop(tag);
}

const Axis = enum(u1) { x = 0, y = 1 };

const SizeKind = enum(u2) {
    fit,
    grow,
    fixed,
    percent,
};

const Size = packed struct {
    pub const zero: Size = .{
        .value = 0,
        .min = 0,
        .kind = .fixed,
    };

    value: f32,
    min: f32,
    kind: SizeKind,
};

const Block = struct {
    pub const empty: Block = .{
        .childrens = .empty,
        .next = null,
        .prev = null,
        .parent = null,
        .axis = .x,
        .sizing = .{ .zero, .zero },
        .size = .{ 0.0, 0.0 },
        .position = .{ 0.0, 0.0 },
        .color = .{ 0.0, 0.0, 0.0, 0.0 },
    };

    childrens: DoublyLinkedList(Block),

    next: ?*Block,
    prev: ?*Block,

    parent: ?*Block,

    axis: Axis,
    sizing: [2]Size,

    size: [2]f32,
    position: [2]f32,
    color: [4]f32,

    pub fn new() !*Block {
        const state = curr_state orelse unreachable;
        const arena = state.frameArena();
        const block = try arena.create(Block);
        block.* = .empty;

        state.block_count += 1;

        if (state.stack.get(.ancestors).head) |parent| {
            parent.block.childrens.prepend(block);
            block.parent = parent.block;
        }

        if (state.stack.get(.axis).head) |n| block.axis = n.axis;
        if (state.stack.get(.color).head) |n| block.color = n.color;
        if (state.stack.get(.width).head) |n| block.sizing[0] = n.size;
        if (state.stack.get(.height).head) |n| block.sizing[1] = n.size;

        return block;
    }
};

test "Basic Operations" {
    const gpa = testing.allocator;
    const io = testing.io;

    var window_state: WindowState = undefined;
    try window_state.init(&.{}, .default, gpa, io);
    defer window_state.deinit();

    const state = &window_state.view_state;

    {
        try startBuild(&window_state);
        endBuild();

        try testing.expectEqual(1, state.block_count);
    }

    {
        try startBuild(&window_state);

        const first = try Block.new();

        endBuild();

        try testing.expectEqual(2, state.block_count);
        const root = state.root;
        try testing.expectEqual(first, root.childrens.last);
    }
}
