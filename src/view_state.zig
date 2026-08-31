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
    state.stacks = .empty;

    curr_state = state;

    const root = try Block.new();
    state.root = root;
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
    frame: u64,
    frame_arenas: [2]heap.ArenaAllocator,
    stacks: LinkedListCollection(Stacks),

    chunks: chunk_pool.ChunkAllocator,

    pub fn init(self: *ViewState, gpa: Allocator) !void {
        self.* = .{
            .stacks = .empty,
            .root = &null_block,
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

const Stacks = union(enum) {
    ancestors: struct { next: ?*@This() = null, block: *Block },
    axis: struct { next: ?*@This() = null, axis: Axis },
    color: struct { next: ?*@This() = null, color: [4]f32 },
};

fn StackNode(comptime tag: std.meta.Tag(Stacks)) type {
    return @FieldType(Stacks, @tagName(tag));
}

pub fn push(comptime tag: std.meta.Tag(Stacks), data: StackNode(tag)) !void {
    const state = curr_state orelse unreachable;
    const node = try state.frameArena().create(StackNode(tag));
    node.* = data;
    node.next = null;
    state.stacks.prepend(tag, node);
}

pub fn pop(comptime tag: std.meta.Tag(Stacks)) ?*StackNode(tag) {
    const state = curr_state orelse unreachable;
    return state.stacks.pop(tag);
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

        return block;
    }
};

test "pushes and pops view stacks by tag" {
    var state: ViewState = undefined;
    try state.init(testing.allocator);
    defer state.deinit();

    curr_state = &state;
    defer curr_state = null;

    try push(.ancestors, .{ .block = &null_block });
    try push(.axis, .{ .axis = .x });
    try push(.axis, .{ .axis = .y });
    try push(.color, .{ .color = .{ 1.0, 0.5, 0.25, 1.0 } });

    const ancestor = pop(.ancestors).?;
    try testing.expect(ancestor.block == &null_block);

    try testing.expectEqual(Axis.y, pop(.axis).?.axis);
    try testing.expectEqual(Axis.x, pop(.axis).?.axis);

    try testing.expectEqual(
        [4]f32{ 1.0, 0.5, 0.25, 1.0 },
        pop(.color).?.color,
    );

    try testing.expect(pop(.ancestors) == null);
    try testing.expect(pop(.axis) == null);
    try testing.expect(pop(.color) == null);
}
