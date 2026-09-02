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

    const size = window_state.size;
    try nextAttrs(&.{
        .{ .width = .{ .fixed = size.width } },
        .{ .height = .{ .fixed = size.height } },
    });
    const root = try block(.{});
    state.root = root;

    try pushAttr(.{ .parent = root });
}

pub fn end() void {
    const state = curr_state orelse unreachable;
    defer curr_state = null;

    inline for (@typeInfo(Axis).@"enum".fields) |field| {
        const axis = field.value;

        {
            var iterator = state.preOrderIterator();
            while (iterator.next()) |b| {
                switch (b.sizing[axis]) {
                    .fixed => |size| b.size[axis] = size,
                    .percent => |percent| {
                        const parent_size = bkl: {
                            var node = b.parent;
                            while (node) |n| : (node = n.next) {
                                switch (n.sizing[axis]) {
                                    .fixed, .percent => break :bkl n.size[axis],
                                    else => {},
                                }
                            }

                            break :bkl 0.0;
                        };

                        b.size[axis] = parent_size * percent;
                    },
                    else => {},
                }
            }
        }

        {
            var iterator = state.postOrderIterator();
            while (iterator.next()) |b| {
                switch (b.sizing[axis]) {
                    .fit => {
                        var total: f32 = 0.0;
                        var children: ?*Block = b.childrens.first;
                        while (children) |child| : (children = child.next) {
                            if (@intFromEnum(b.axis) == axis) {
                                total += child.size[axis];
                            } else {
                                total = @max(total, child.size[axis]);
                            }
                        }

                        b.size[axis] = total;
                    },
                    else => {},
                }
            }
        }

        {
            var iterator = state.preOrderIterator();
            while (iterator.next()) |b| {
                const allowed = b.size[axis];

                if (@intFromEnum(b.axis) != axis and
                    b.flags.overflow & (@as(u2, 1) << axis) == 0)
                {
                    var children = b.childrens.first;
                    while (children) |child| : (children = child.next) {
                        const size = child.size[axis];
                        const overflow = size - allowed;
                        const fix = std.math.clamp(overflow, 0, size);
                        if (fix > 0) child.size[axis] -= fix;
                    }
                }

                if (@intFromEnum(b.axis) == axis and
                    b.flags.overflow & (@as(u2, 1) << axis) == 0)
                {
                    var used: f32 = 0.0;
                    var aviable: f32 = 0.0;

                    var children = b.childrens.first;
                    while (children) |child| : (children = child.next) {
                        used += child.size[axis];
                        aviable += child.size[axis] * (1.0 - child.minimum[axis]);
                    }

                    const overflow = used - allowed;

                    if (overflow > 0 and aviable > 0) {
                        const fixup = std.math.clamp(overflow / aviable, 0, 1);
                        children = b.childrens.first;

                        while (children) |child| : (children = child.next) {
                            child.size[axis] -= child.size[axis] * (1.0 - child.minimum[axis]) * fixup;
                        }
                    }
                }

                if (b.flags.overflow & (@as(u2, 1) << axis) == 1) {
                    var children = b.childrens.first;
                    while (children) |child| : (children = child.next) {
                        switch (child.sizing[axis]) {
                            .percent => |percent| {
                                child.size[axis] = b.size[axis] * percent;
                            },
                            else => {},
                        }
                    }
                }
            }
        }

        {
            var iterator = state.preOrderIterator();
            while (iterator.next()) |b| {
                var position: f32 = 0.0;
                var bounds: f32 = 0.0;

                var children: ?*Block = b.childrens.first;
                while (children) |child| : (children = child.next) {
                    child.position[axis] = position;

                    if (@intFromEnum(b.axis) == axis) {
                        position += child.size[axis];
                        bounds += child.size[axis];
                    } else {
                        bounds = @max(bounds, child.size[axis]);
                    }

                    child.abs_position[axis] = b.abs_position[axis] + child.position[axis];
                }

                b.bounds[axis] = bounds;
            }
        }
    }

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

pub fn pushAttr(attr: ViewState.Attribute) !void {
    const state = curr_state orelse unreachable;
    const arena = state.frameArena();

    switch (attr) {
        inline else => |val, flag| {
            assert(state.pop_flags & stackFlag(flag) == 0);

            const node = try arena.create(ViewState.Node(flag));
            node.* = .{ .value = val };
            state.stacks.prepend(flag, node);
        },
    }
}

pub fn popAttr(comptime flag: ViewState.Flags) void {
    const state = curr_state orelse unreachable;

    assert(state.pop_flags & stackFlag(flag) == 0);

    if (state.stacks.pop(flag) == null) unreachable;
}

pub fn nextAttr(attr: ViewState.Attribute) !void {
    const state = curr_state orelse unreachable;

    try pushAttr(attr);
    state.flagStack(meta.activeTag(attr));
}

pub fn nextAttrs(values: []const ViewState.Attribute) !void {
    for (values) |value| {
        try nextAttr(value);
    }
}

pub fn block(flags: Block.Flags) !*Block {
    const state = curr_state orelse unreachable;
    const arena = state.frameArena();

    const new = try arena.create(Block);
    new.* = ._null;

    state.block_count += 1;

    if (state.stacks.get(.parent).head) |parent| {
        parent.value.child_count += 1;
        parent.value.childrens.append(new);
        new.parent = parent.value;
    }

    if (state.stacks.get(.color).head) |node| new.color = node.value;

    if (state.stacks.get(.axis).head) |node| new.axis = node.value;

    if (state.stacks.get(.width).head) |node| new.sizing[0] = node.value;
    if (state.stacks.get(.width_strictness).head) |node| new.minimum[0] = std.math.clamp(node.value, 0.0, 1.0);

    if (state.stacks.get(.height).head) |node| new.sizing[1] = node.value;
    if (state.stacks.get(.height_strictness).head) |node| new.minimum[1] = std.math.clamp(node.value, 0.0, 1.0);

    const stack_flags: u2 = if (state.stacks.get(.flags).head) |node| @bitCast(node.value) else 0;
    new.flags = @bitCast(@as(u2, @bitCast(flags)) | stack_flags);

    state.popFlagged();

    return new;
}

fn stackFlag(flag: ViewState.Flags) u64 {
    return @as(u64, 1) << @intFromEnum(flag);
}

pub const ViewState = struct {
    const Stacks = TaggedLinkedList(union(enum) {
        parent: *Block,
        axis: Axis,
        color: [4]f32,
        width: Size,
        width_strictness: f32,
        height: Size,
        height_strictness: f32,
        alignment: [2]Alignment,
        flags: Block.Flags,
    });

    pub const Flags = Stacks.Tag;

    pub const Attribute = Stacks.Value;

    pub const Node = Stacks.Node;

    arena: heap.ArenaAllocator,

    root: *Block,
    block_count: u64,

    frame: u64,
    frame_arenas: [2]heap.ArenaAllocator,

    stacks: Stacks,
    pop_flags: u64,

    chunks: chunk_pool.ChunkAllocator,

    pub fn init(self: *ViewState, gpa: Allocator) !void {
        self.* = .{
            .stacks = .empty,
            .pop_flags = 0,
            .root = undefined,
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

    pub fn reset(self: *ViewState) void {
        self.root = undefined;
        self.stacks = .empty;
        self.pop_flags = 0;
        self.block_count = 0;
    }

    pub fn flagStack(
        self: *ViewState,
        flag: Flags,
    ) void {
        self.pop_flags |= stackFlag(flag);
    }

    pub fn popFlagged(self: *ViewState) void {
        inline for (@typeInfo(Stacks.Tag).@"enum".fields) |field| {
            const flag: Flags = @enumFromInt(field.value);
            if (self.pop_flags & stackFlag(flag) != 0) {
                self.pop_flags &= ~stackFlag(flag);
                if (self.stacks.pop(flag) == null) unreachable;
            }
        }
    }

    const PreOrderIterator = struct {
        node: ?*Block,

        pub fn next(self: *PreOrderIterator) ?*Block {
            const current = self.node orelse return null;
            self.node = nextPreOrder(current);

            return current;
        }

        fn nextPreOrder(current: *Block) ?*Block {
            if (current.childrens.first) |child| return child;

            var ancestor = current;
            while (true) {
                if (ancestor.next) |sibling| return sibling;
                ancestor = ancestor.parent orelse return null;
            }
        }
    };

    const PostOrderIterator = struct {
        node: ?*Block,

        pub fn next(self: *PostOrderIterator) ?*Block {
            const current = self.node orelse return null;
            self.node = nextPostOrder(current);

            return current;
        }

        fn nextPostOrder(current: *Block) ?*Block {
            const parent = current.parent orelse return null;
            return if (current.next) |sibling| firstPostOrder(sibling) else parent;
        }
    };

    pub fn preOrderIterator(self: *ViewState) PreOrderIterator {
        return .{ .node = self.root };
    }

    pub fn postOrderIterator(self: *ViewState) PostOrderIterator {
        return .{ .node = firstPostOrder(self.root) };
    }

    fn firstPostOrder(root: *Block) *Block {
        var node = root;
        while (node.childrens.first) |child| node = child;
        return node;
    }
};

const Axis = enum(u1) { x = 0, y = 1 };

const Size = union(enum) {
    const zero: Size = .{ .fixed = 0 };
    const grow: Size = .{ .percent = 1 };

    fit,
    fixed: f32,
    percent: f32,
};

const Alignment = enum(u2) {
    none,
    start,
    center,
    end,
};

const Block = struct {
    const Flags = packed struct {
        const allowOverflow: Flags = .{
            .overflow = 0b11,
        };

        overflow: u2 = 0,
    };

    pub const _null: Block = .{
        .minimum = @splat(0.0),
        .childrens = .empty,
        .next = null,
        .prev = null,
        .parent = null,
        .axis = .x,
        .sizing = @splat(.zero),
        .size = @splat(0.0),
        .position = @splat(0.0),
        .bounds = @splat(0.0),
        .abs_position = @splat(0.0),
        .color = @splat(0.0),
        .alignment = @splat(.none),
        .flags = .{},
        .child_count = 0,
    };

    childrens: DoublyLinkedList(Block),
    child_count: u8,

    next: ?*Block,
    prev: ?*Block,

    parent: ?*Block,
    axis: Axis,
    sizing: [2]Size,
    minimum: [2]f32,
    color: [4]f32,
    alignment: [2]Alignment,
    flags: Flags,

    size: [2]f32,
    position: [2]f32,
    abs_position: [2]f32,
    bounds: [2]f32,
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

        try testing.expectEqual(1, state.block_count);
    }

    {
        try start(&window_state);

        const first = try block(.{});

        end();

        try testing.expectEqual(2, state.block_count);
        const root = state.root;
        try testing.expectEqual(first, root.childrens.last);
    }

    try start(&window_state);
    defer end();

    const color = [4]f32{ 1.0, 0.5, 0.25, 1.0 };

    {
        try nextAttr(.{ .axis = .y });
        try nextAttr(.{ .color = color });

        const styled = try block(.{});
        try testing.expectEqual(Axis.y, styled.axis);
        try testing.expectEqual(color, styled.color);
        try testing.expect(window_state.view_state.stacks.get(.axis).is_empty());
        try testing.expect(window_state.view_state.stacks.get(.color).is_empty());
        try testing.expectEqual(@as(u64, 0), window_state.view_state.pop_flags);
    }

    {
        try nextAttrs(&.{
            .{ .axis = .y },
            .{ .color = color },
        });

        const styled = try block(.{});
        try testing.expectEqual(Axis.y, styled.axis);
        try testing.expectEqual(color, styled.color);
        try testing.expect(window_state.view_state.stacks.get(.axis).is_empty());
        try testing.expect(window_state.view_state.stacks.get(.color).is_empty());
        try testing.expectEqual(@as(u64, 0), window_state.view_state.pop_flags);
    }

    const unstyled = try block(.{});
    try testing.expectEqual(Axis.x, unstyled.axis);
    try testing.expectEqual(Block._null.color, unstyled.color);

    {
        try pushAttr(.{ .axis = .y });
        defer popAttr(.axis);
    }

    try pushAttr(.{ .axis = .x });
    defer popAttr(.axis);

    const manually_popped = try block(.{});
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

        try pushAttr(.{ .flags = .allowOverflow });

        try nextAttrs(&.{ .{ .width = .grow }, .{ .height = .grow } });
        const wrapper = try block(.{});
        try pushAttr(.{ .parent = wrapper });

        try nextAttrs(&.{ .{ .width = .{ .fixed = 800 } }, .{ .height = .{ .fixed = 800 } } });
        const first = try block(.{});

        try pushAttr(.{ .parent = first });
        try nextAttrs(&.{ .{ .width = .{ .fixed = 400 } }, .{ .height = .{ .fixed = 800 } } });
        const first_first = try block(.{});

        try nextAttrs(&.{ .{ .width = .{ .fixed = 400 } }, .{ .height = .{ .fixed = 800 } } });
        const first_second = try block(.{});
        popAttr(.parent);

        try nextAttrs(&.{ .{ .width = .{ .fixed = 120 } }, .{ .height = .{ .fixed = 120 } }, .{ .axis = .y } });
        const second = try block(.{});

        try pushAttr(.{ .parent = second });
        try nextAttrs(&.{ .{ .width = .{ .fixed = 120 } }, .{ .height = .{ .fixed = 60 } } });
        const second_first = try block(.{});

        try nextAttrs(&.{ .{ .width = .{ .fixed = 120 } }, .{ .height = .{ .fixed = 60 } } });
        const second_second = try block(.{});
        popAttr(.parent);

        try nextAttrs(&.{ .{ .width = .{ .fixed = 509 } }, .{ .height = .{ .fixed = 789 } } });
        const third = try block(.{});

        try pushAttr(.{ .parent = third });
        try nextAttrs(&.{ .{ .width = .{ .fixed = 600 } }, .{ .height = .{ .fixed = 800 } } });
        const third_first = try block(.{});

        popAttr(.parent);
        popAttr(.parent);
        popAttr(.flags);

        end();

        try testing.expectEqual([2]f32{ 800, 800 }, first.size);
        try testing.expectEqual([2]f32{ 120, 120 }, second.size);
        try testing.expectEqual([2]f32{ 509, 789 }, third.size);

        try testing.expectEqual([2]f32{ 0, 0 }, first.position);
        try testing.expectEqual([2]f32{ 0, 0 }, first.abs_position);
        try testing.expectEqual([2]f32{ 800, 800 }, first.bounds);

        try testing.expectEqual([2]f32{ 0, 0 }, first_first.position);
        try testing.expectEqual([2]f32{ 0, 0 }, first_first.abs_position);
        try testing.expectEqual([2]f32{ 0, 0 }, first_first.bounds);

        try testing.expectEqual([2]f32{ 400, 0 }, first_second.position);
        try testing.expectEqual([2]f32{ 400, 0 }, first_second.abs_position);
        try testing.expectEqual([2]f32{ 0, 0 }, first_second.bounds);

        try testing.expectEqual([2]f32{ 800, 0 }, second.position);
        try testing.expectEqual([2]f32{ 800, 0 }, second.abs_position);
        try testing.expectEqual([2]f32{ 120, 120 }, second.bounds);

        try testing.expectEqual([2]f32{ 0, 0 }, second_first.position);
        try testing.expectEqual([2]f32{ 800, 0 }, second_first.abs_position);
        try testing.expectEqual([2]f32{ 0, 0 }, second_first.bounds);

        try testing.expectEqual([2]f32{ 0, 60 }, second_second.position);
        try testing.expectEqual([2]f32{ 800, 60 }, second_second.abs_position);
        try testing.expectEqual([2]f32{ 0, 0 }, second_second.bounds);

        try testing.expectEqual([2]f32{ 920, 0 }, third.position);
        try testing.expectEqual([2]f32{ 920, 0 }, third.abs_position);
        try testing.expectEqual([2]f32{ 600, 800 }, third.bounds);

        try testing.expectEqual([2]f32{ 0, 0 }, third_first.position);
        try testing.expectEqual([2]f32{ 920, 0 }, third_first.abs_position);
        try testing.expectEqual([2]f32{ 0, 0 }, third_first.bounds);
    }
}

test "Percent Layout" {
    const gpa = testing.allocator;
    const io = testing.io;

    var window_state: WindowState = undefined;
    try window_state.init(&.{}, .default, gpa, io);
    defer window_state.deinit();

    try start(&window_state);

    try nextAttrs(&.{ .{ .width = .{ .fixed = 600 } }, .{ .height = .{ .fixed = 800 } } });
    const parent = try block(.{});

    try pushAttr(.{ .parent = parent });
    try nextAttrs(&.{ .{ .width = .{ .percent = 0.25 } }, .{ .height = .{ .percent = 0.5 } } });
    const first = try block(.{});

    try pushAttr(.{ .parent = first });
    try nextAttrs(&.{ .{ .width = .{ .percent = 0.5 } }, .{ .height = .{ .percent = 0.5 } } });
    const nested = try block(.{});
    popAttr(.parent);

    try nextAttrs(&.{ .{ .width = .{ .percent = 0.5 } }, .{ .height = .{ .percent = 1.0 } } });
    const second = try block(.{});
    popAttr(.parent);

    end();

    try testing.expectEqual([2]f32{ 600, 800 }, parent.size);
    try testing.expectEqual([2]f32{ 450, 800 }, parent.bounds);

    try testing.expectEqual([2]f32{ 150, 400 }, first.size);
    try testing.expectEqual([2]f32{ 0, 0 }, first.position);
    try testing.expectEqual([2]f32{ 0, 0 }, first.abs_position);
    try testing.expectEqual([2]f32{ 75, 200 }, first.bounds);

    try testing.expectEqual([2]f32{ 75, 200 }, nested.size);
    try testing.expectEqual([2]f32{ 0, 0 }, nested.position);
    try testing.expectEqual([2]f32{ 0, 0 }, nested.abs_position);
    try testing.expectEqual([2]f32{ 0, 0 }, nested.bounds);

    try testing.expectEqual([2]f32{ 300, 800 }, second.size);
    try testing.expectEqual([2]f32{ 150, 0 }, second.position);
    try testing.expectEqual([2]f32{ 150, 0 }, second.abs_position);
    try testing.expectEqual([2]f32{ 0, 0 }, second.bounds);
}

test "Full Percent Width With Fixed Siblings" {
    const gpa = testing.allocator;
    const io = testing.io;

    var window_state: WindowState = undefined;
    try window_state.init(&.{}, .default, gpa, io);
    defer window_state.deinit();

    try start(&window_state);

    try nextAttrs(&.{ .{ .width = .grow }, .{ .height = .grow } });
    const parent = try block(.{});

    try pushAttr(.{ .parent = parent });
    try nextAttrs(&.{
        .{ .width = .{ .fixed = 100 } },
        .{ .height = .grow },
        .{ .height_strictness = 1.0 },
        .{ .width_strictness = 1.0 },
    });
    const first = try block(.{});

    try nextAttrs(&.{ .{ .width = .grow }, .{ .height = .grow } });
    const middle = try block(.{});

    try nextAttrs(&.{
        .{ .width = .{ .fixed = 100 } },
        .{ .height = .grow },
        .{ .height_strictness = 1.0 },
        .{ .width_strictness = 1.0 },
    });
    const last = try block(.{});
    popAttr(.parent);

    end();

    try testing.expectEqual([2]f32{ 600, 800 }, parent.size);
    try testing.expectEqual([2]f32{ 600, 800 }, parent.bounds);

    try testing.expectEqual([2]f32{ 100, 800 }, first.size);
    try testing.expectEqual([2]f32{ 0, 0 }, first.position);
    try testing.expectEqual([2]f32{ 0, 0 }, first.abs_position);

    try testing.expectEqual([2]f32{ 400, 800 }, middle.size);
    try testing.expectEqual([2]f32{ 100, 0 }, middle.position);
    try testing.expectEqual([2]f32{ 100, 0 }, middle.abs_position);

    try testing.expectEqual([2]f32{ 100, 800 }, last.size);
    try testing.expectEqual([2]f32{ 500, 0 }, last.position);
    try testing.expectEqual([2]f32{ 500, 0 }, last.abs_position);
}
//
// test "Fit Layout" {
//     const gpa = testing.allocator;
//     const io = testing.io;
//
//     var window_state: WindowState = undefined;
//     try window_state.init(&.{}, .default, gpa, io);
//     defer window_state.deinit();
//
//     try start(&window_state);
//
//     try nextAttrs(&.{ .{ .width = .{ .fixed = 100 } }, .{ .height = .{ .fixed = 100 } } });
//     const spacer = try block();
//
//     try nextAttrs(&.{ .{ .width = .fit }, .{ .height = .fit }, .{ .axis = .y } });
//     const parent = try block();
//
//     try pushAttr(.{ .parent = parent });
//     try nextAttrs(&.{ .{ .width = .fit }, .{ .height = .fit } });
//     const first = try block();
//
//     try pushAttr(.{ .parent = first });
//     try nextAttrs(&.{ .{ .width = .{ .fixed = 100 } }, .{ .height = .{ .fixed = 150 } } });
//     const first_first = try block();
//
//     try nextAttrs(&.{ .{ .width = .{ .fixed = 100 } }, .{ .height = .{ .fixed = 150 } } });
//     const first_second = try block();
//     popAttr(.parent);
//
//     try nextAttrs(&.{ .{ .width = .{ .fixed = 400 } }, .{ .height = .{ .fixed = 450 } } });
//     const second = try block();
//     popAttr(.parent);
//
//     end();
//
//     try testing.expectEqual([2]f32{ 100, 100 }, spacer.size);
//     try testing.expectEqual([2]f32{ 0, 0 }, spacer.position);
//     try testing.expectEqual([2]f32{ 0, 0 }, spacer.abs_position);
//     try testing.expectEqual([2]f32{ 0, 0 }, spacer.bounds);
//
//     try testing.expectEqual([2]f32{ 400, 600 }, parent.size);
//     try testing.expectEqual([2]f32{ 100, 0 }, parent.position);
//     try testing.expectEqual([2]f32{ 100, 0 }, parent.abs_position);
//     try testing.expectEqual([2]f32{ 400, 600 }, parent.bounds);
//
//     try testing.expectEqual([2]f32{ 200, 150 }, first.size);
//     try testing.expectEqual([2]f32{ 0, 0 }, first.position);
//     try testing.expectEqual([2]f32{ 100, 0 }, first.abs_position);
//     try testing.expectEqual([2]f32{ 200, 150 }, first.bounds);
//
//     try testing.expectEqual([2]f32{ 100, 150 }, first_first.size);
//     try testing.expectEqual([2]f32{ 0, 0 }, first_first.position);
//     try testing.expectEqual([2]f32{ 100, 0 }, first_first.abs_position);
//     try testing.expectEqual([2]f32{ 0, 0 }, first_first.bounds);
//
//     try testing.expectEqual([2]f32{ 100, 150 }, first_second.size);
//     try testing.expectEqual([2]f32{ 100, 0 }, first_second.position);
//     try testing.expectEqual([2]f32{ 200, 0 }, first_second.abs_position);
//     try testing.expectEqual([2]f32{ 0, 0 }, first_second.bounds);
//
//     try testing.expectEqual([2]f32{ 400, 450 }, second.size);
//     try testing.expectEqual([2]f32{ 0, 150 }, second.position);
//     try testing.expectEqual([2]f32{ 100, 150 }, second.abs_position);
//     try testing.expectEqual([2]f32{ 0, 0 }, second.bounds);
// }
