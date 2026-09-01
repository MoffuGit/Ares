// The following Immedate Mode GUI implementation concepts origined from
// Digital Grove(https://www.dgtlgrove.com/)

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

pub fn start(window_state: *WindowState) !void {
    assert(curr_state == null);

    const state = &window_state.view_state;
    state.reset();

    curr_state = state;

    const root = try box();
    state.root = root;

    try pushAttr(.{ .parent = root });
}

pub fn end() void {
    const state = curr_state orelse unreachable;
    defer curr_state = null;

    inline for (@typeInfo(Axis).@"enum".fields) |field| {
        const axis = field.value;

        var curr: ?*Box = state.root;

        while (curr) |b| {
            switch (b.sizing[axis]) {
                .fixed => |size| b.size[axis] = size,
                else => {},
            }

            curr = null;
        }
    }

    //we need to produce our layout
    //lets do first width
    //then height
    //
    //width;
    //fit size ,
    //grow/shrink
    //wrap text (not yet)
    //
    //height
    //fit size
    //grow/srhink
    //
    //positions and alignment
    //
    //after we have the layout Algorithm
    //i want to add the cache
    //and after the cache i want to add signals( input events )
    //
    //another thing we would need to add are more styles (not only bg color)
    //those are thing like borders, corner radius, blur, transparency...

    state.frame += 1;
    const arena_index = state.frame % state.frame_arenas.len;
    _ = state.frame_arenas[arena_index].reset(.retain_capacity);
}

pub fn pushAttr(attr: Attribute) !void {
    const state = curr_state orelse unreachable;
    const arena = state.frameArena();

    switch (attr) {
        inline else => |val, flag| {
            assert(state.stack_pop_flags & stackFlag(flag) == 0);

            const node = try arena.create(Stacks.Node(flag));
            node.* = .{ .value = val };
            state.stacks.prepend(flag, node);
        },
    }
}

pub fn popAttr(comptime flag: Flags) void {
    const state = curr_state orelse unreachable;

    assert(state.stack_pop_flags & stackFlag(flag) == 0);

    if (state.stacks.pop(flag) == null) unreachable;
}

pub fn nextAttr(attr: Attribute) !void {
    const state = curr_state orelse unreachable;

    try pushAttr(attr);
    state.flagStack(meta.activeTag(attr));
}

pub fn nextAttrs(values: []const Attribute) !void {
    for (values) |value| {
        try nextAttr(value);
    }
}

pub fn box() !*Box {
    const state = curr_state orelse unreachable;
    const arena = state.frameArena();

    const new = try arena.create(Box);
    new.* = ._null;

    state.box_count += 1;

    if (state.stacks.get(.parent).head) |parent| {
        parent.value.childrens.prepend(new);
        new.parent = parent.value;
    }

    if (state.stacks.get(.color).head) |node| new.color = node.value;

    if (state.stacks.get(.axis).head) |node| new.axis = node.value;

    if (state.stacks.get(.width).head) |node| new.sizing[0] = node.value;
    if (state.stacks.get(.min_width).head) |node| new.minimum[0] = node.value;

    if (state.stacks.get(.height).head) |node| new.sizing[1] = node.value;
    if (state.stacks.get(.min_height).head) |node| new.minimum[1] = node.value;

    state.popFlagged();

    return new;
}

const Stacks = TaggedLinkedList(union(enum) {
    parent: *Box,
    axis: Axis,
    color: [4]f32,
    width: Size,
    min_width: f32,
    height: Size,
    min_height: f32,
    alignment: [2]Alignment,
    padding: [4]f32,
    gap: f32,
});

pub const Flags = Stacks.Tag;
pub const Attribute = Stacks.Value;

fn stackFlag(flag: Flags) u64 {
    return @as(u64, 1) << @intFromEnum(flag);
}

pub const ViewState = struct {
    arena: heap.ArenaAllocator,

    root: *Box,
    box_count: u64,

    frame: u64,
    frame_arenas: [2]heap.ArenaAllocator,

    stacks: Stacks,
    stack_pop_flags: u64,

    chunks: chunk_pool.ChunkAllocator,

    pub fn init(self: *ViewState, gpa: Allocator) !void {
        self.* = .{
            .stacks = .empty,
            .stack_pop_flags = 0,
            .root = undefined,
            .box_count = 0,
            .frame = 0,
            .frame_arenas = .{ .init(gpa), .init(gpa) },
            .arena = .init(gpa),
            .chunks = undefined,
        };

        const arena = self.arena.allocator();
        errdefer self.arena.deinit();

        try self.chunks.init(arena, &.{.{ .capacity = 2048, .chunk_size = @sizeOf(Box) }});
    }

    pub fn deinit(self: *ViewState) void {
        for (self.frame_arenas) |arena| arena.deinit();
        self.arena.deinit();
    }

    pub fn frameArena(self: *ViewState) Allocator {
        return self.frame_arenas[self.frame % self.frame_arenas.len].allocator();
    }

    pub fn reset(self: *ViewState) void {
        self.root = undefined;
        self.stacks = .empty;
        self.stack_pop_flags = 0;
        self.box_count = 0;
    }

    pub fn flagStack(
        self: *ViewState,
        flag: Flags,
    ) void {
        self.stack_pop_flags |= stackFlag(flag);
    }

    pub fn popFlagged(self: *ViewState) void {
        inline for (@typeInfo(Stacks.Tag).@"enum".fields) |field| {
            const flag: Flags = @enumFromInt(field.value);
            if (self.stack_pop_flags & stackFlag(flag) != 0) {
                self.stack_pop_flags &= ~stackFlag(flag);
                if (self.stacks.pop(flag) == null) unreachable;
            }
        }
    }
};

const Axis = enum(u1) { x = 0, y = 1 };

const Size = union(enum) {
    const zero: Size = .{ .fixed = 0 };

    fit: f32,
    grow: f32,
    fixed: f32,
    percent: f32,
};

const Alignment = enum(u2) {
    none,
    start,
    center,
    end,
};

const Box = struct {
    pub const _null: Box = .{
        .minimum = @splat(0.0),
        .childrens = .empty,
        .next = null,
        .prev = null,
        .parent = null,
        .axis = .x,
        .sizing = @splat(.zero),
        .size = @splat(0.0),
        .position = @splat(0.0),
        .color = @splat(0.0),
        .padding = @splat(0.0),
        .gap = 0,
        .alignment = @splat(.none),
    };

    childrens: DoublyLinkedList(Box),

    next: ?*Box,
    prev: ?*Box,

    parent: ?*Box,
    axis: Axis,
    sizing: [2]Size,
    minimum: [2]f32,
    color: [4]f32,
    padding: [4]f32,
    gap: f32,
    alignment: [2]Alignment,

    size: [2]f32,
    position: [2]f32,
};

test "Basic Operations" {
    const gpa = testing.allocator;
    const io = testing.io;

    var window_state: WindowState = undefined;
    try window_state.init(&.{}, .default, gpa, io);
    defer window_state.deinit();

    const state = &window_state.view_state;

    {
        try start(&window_state);
        end();

        try testing.expectEqual(1, state.box_count);
    }

    {
        try start(&window_state);

        const first = try box();

        end();

        try testing.expectEqual(2, state.box_count);
        const root = state.root;
        try testing.expectEqual(first, root.childrens.last);
    }

    try start(&window_state);
    defer end();

    const color = [4]f32{ 1.0, 0.5, 0.25, 1.0 };

    {
        try nextAttr(.{ .axis = .y });
        try nextAttr(.{ .color = color });

        const styled = try box();
        try testing.expectEqual(Axis.y, styled.axis);
        try testing.expectEqual(color, styled.color);
        try testing.expect(window_state.view_state.stacks.get(.axis).is_empty());
        try testing.expect(window_state.view_state.stacks.get(.color).is_empty());
        try testing.expectEqual(@as(u64, 0), window_state.view_state.stack_pop_flags);
    }

    {
        try nextAttrs(&.{
            .{ .axis = .y },
            .{ .color = color },
        });

        const styled = try box();
        try testing.expectEqual(Axis.y, styled.axis);
        try testing.expectEqual(color, styled.color);
        try testing.expect(window_state.view_state.stacks.get(.axis).is_empty());
        try testing.expect(window_state.view_state.stacks.get(.color).is_empty());
        try testing.expectEqual(@as(u64, 0), window_state.view_state.stack_pop_flags);
    }

    const unstyled = try box();
    try testing.expectEqual(Axis.x, unstyled.axis);
    try testing.expectEqual(Box._null.color, unstyled.color);

    {
        try pushAttr(.{ .axis = .y });
        defer popAttr(.axis);
    }

    try pushAttr(.{ .axis = .x });
    defer popAttr(.axis);

    const manually_popped = try box();
    try testing.expectEqual(Axis.x, manually_popped.axis);
    try testing.expect(window_state.view_state.stacks.get(.axis).head != null);
}

test "Fixed Layout" {
    const gpa = testing.allocator;
    const io = testing.io;

    var window_state: WindowState = undefined;
    try window_state.init(&.{}, .default, gpa, io);
    defer window_state.deinit();

    {
        try start(&window_state);
        defer end();

        try nextAttrs(&.{ .{ .width = .{ .fixed = 800 } }, .{ .height = .{ .fixed = 800 } } });
        _ = try box();

        try nextAttrs(&.{ .{ .width = .{ .fixed = 120 } }, .{ .height = .{ .fixed = 120 } } });
        _ = try box();

        try nextAttrs(&.{ .{ .width = .{ .fixed = 509 } }, .{ .height = .{ .fixed = 789 } } });
        _ = try box();
    }
}
