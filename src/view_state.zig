// // The following Immedate Mode GUI implementation concepts origined from
// // Digital Grove(https://www.dgtlgrove.com/)

const std = @import("std");
const Allocator = std.mem.Allocator;
const heap = std.heap;
const assert = std.debug.assert;
const testing = std.testing;
const meta = std.meta;

const App = @import("app.zig");
const WindowState = App.WindowState;
const chunk_pool = @import("chunk_pool.zig");
const datastruct = @import("datastruct.zig");
const DoublyLinkedList = datastruct.DoublyLinkedList;
const TaggedLinkedList = datastruct.TaggedLinkedList;

pub var curr_state: ?*ViewState = null;
pub var null_block: Block = .empty;

pub fn startBuild(window_state: *WindowState) !void {
    assert(curr_state == null);

    const state = &window_state.view_state;
    state.root = &null_block;
    state.stacks = .empty;
    state.auto_pop_flags = 0;
    state.block_count = 0;

    curr_state = state;

    const root = try Block.new();
    state.root = root;

    try push(.{ .ancestors = root });
}

pub fn endBuild() void {
    const state = curr_state orelse unreachable;
    state.frame += 1;
    const arena_index = state.frame % state.frame_arenas.len;
    _ = state.frame_arenas[arena_index].reset(.retain_capacity);

    curr_state = null;
}

pub const ViewState = struct {
    arena: heap.ArenaAllocator,

    root: *Block,
    block_count: u64,

    frame: u64,
    frame_arenas: [2]heap.ArenaAllocator,

    stacks: StackCollection,
    auto_pop_flags: u64,

    chunks: chunk_pool.ChunkAllocator,

    pub fn init(self: *ViewState, gpa: Allocator) !void {
        self.* = .{
            .stacks = .empty,
            .auto_pop_flags = 0,
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

const Stacks = union(enum) {
    ancestors: *Block,
    axis: Axis,
    color: [4]f32,
    width: Size,
    height: Size,
};

const StackCollection = TaggedLinkedList(Stacks);

fn stackFlag(tag: StackCollection.Tag) u64 {
    return @as(u64, 1) << @intFromEnum(tag);
}

pub fn push(value: Stacks) !void {
    const state = curr_state orelse unreachable;
    assert(state.auto_pop_flags & stackFlag(meta.activeTag(value)) == 0);

    switch (value) {
        inline else => |val, tag| {
            const node = try state.frameArena().create(StackCollection.Node(tag));
            node.* = .{ .value = val };
            state.stacks.prepend(tag, node);
        },
    }
}

pub fn pop(comptime tag: StackCollection.Tag) void {
    const state = curr_state orelse unreachable;
    assert(state.auto_pop_flags & stackFlag(tag) == 0);
    assert(state.stacks.pop(tag) != null);
}

pub fn setNext(value: Stacks) !void {
    const state = curr_state orelse unreachable;
    try push(value);
    state.auto_pop_flags |= stackFlag(meta.activeTag(value));
}

fn popAutomaticStacks() void {
    const state = curr_state orelse unreachable;

    inline for (@typeInfo(StackCollection.Tag).@"enum".fields) |field| {
        const tag: StackCollection.Tag = @enumFromInt(field.value);
        if (state.auto_pop_flags & stackFlag(tag) != 0) {
            state.auto_pop_flags &= ~stackFlag(tag);
            pop(tag);
        }
    }
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
        const block = try state.frameArena().create(Block);
        block.* = .empty;

        state.block_count += 1;

        if (state.stacks.get(.ancestors).head) |parent| {
            parent.value.childrens.prepend(block);
            block.parent = parent.value;
        }

        if (state.stacks.get(.axis).head) |node| block.axis = node.value;
        if (state.stacks.get(.color).head) |node| block.color = node.value;
        if (state.stacks.get(.width).head) |node| block.sizing[0] = node.value;
        if (state.stacks.get(.height).head) |node| block.sizing[1] = node.value;

        popAutomaticStacks();

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

test "pops stacks after creating one block" {
    const gpa = testing.allocator;
    const io = testing.io;

    var window_state: WindowState = undefined;
    try window_state.init(&.{}, .default, gpa, io);
    defer window_state.deinit();

    try startBuild(&window_state);
    defer endBuild();

    const color = [4]f32{ 1.0, 0.5, 0.25, 1.0 };
    try setNext(.{ .axis = .y });
    try setNext(.{ .color = color });

    const styled = try Block.new();
    try testing.expectEqual(Axis.y, styled.axis);
    try testing.expectEqual(color, styled.color);
    try testing.expect(window_state.view_state.stacks.get(.axis).is_empty());
    try testing.expect(window_state.view_state.stacks.get(.color).is_empty());
    try testing.expectEqual(@as(u64, 0), window_state.view_state.auto_pop_flags);

    const unstyled = try Block.new();
    try testing.expectEqual(Axis.x, unstyled.axis);
    try testing.expectEqual(Block.empty.color, unstyled.color);

    {
        try push(.{ .axis = .y });
        defer pop(.axis);
    }

    try push(.{ .axis = .x });
    defer pop(.axis);

    const manually_popped = try Block.new();
    try testing.expectEqual(Axis.x, manually_popped.axis);
    try testing.expect(window_state.view_state.stacks.get(.axis).head != null);
}
