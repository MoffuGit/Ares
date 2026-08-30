const std = @import("std");
const Allocator = std.mem.Allocator;
const heap = std.heap;
const assert = std.debug.assert;
const testing = std.testing;

const App = @import("app.zig");
const WindowState = App.WindowState;
const chunk_pool = @import("chunk_pool.zig");
const datastruct = @import("datastruct.zig");
const MultiQueue = datastruct.MultiQueue;
const DoublyLinkedList = datastruct.DoublyLinkedList;

pub var curr_state: ?*ViewState = null;

pub const ViewState = struct {
    arena: heap.ArenaAllocator,
    frame: u64,
    frame_arenas: [2]heap.ArenaAllocator,
    chunks: chunk_pool.ChunkAllocator,
    root: *Block,

    pub fn init(self: *ViewState, gpa: Allocator) !void {
        self.* = .{
            .root = undefined,
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

pub fn startBuild(window_state: *WindowState) void {
    assert(curr_state == null);

    const state = &window_state.view_state;

    curr_state = state;
}

pub fn endBuild() void {
    const state = curr_state orelse unreachable;
    state.frame += 1;
    _ = state.frame_arenas[state.frame % state.frame_arenas.len].reset(.retain_capacity);

    curr_state = null;
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

test "Basic operation" {
    const gpa = testing.allocator;

    var window_state: WindowState = .{
        .size = .{ .width = 800.0, .height = 600.0 },
        .render_handle = .{},
        .win = .{},
        .view_state = undefined,
    };

    try window_state.view_state.init(gpa);
    defer window_state.view_state.deinit();

    startBuild(&window_state);
    defer endBuild();

    const block = try Block.new();
    _ = block;
}
