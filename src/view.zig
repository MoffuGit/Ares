// The immediate-mode GUI implementation is based on concepts from Digital Grove (https://www.dgtlgrove.com/).

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const clamp = std.math.clamp;
const heap = std.heap;
const meta = std.meta;
const testing = std.testing;

const chunk_pool = @import("chunk_pool.zig");
const datastruct = @import("datastruct.zig");
const DoublyLinkedList = datastruct.DoublyLinkedList;
const TaggedLinkedList = datastruct.TaggedLinkedList;

pub const ViewState = struct {
    arena: heap.ArenaAllocator,
    root: ?*Block,
    block_count: u64,

    frame: u64,
    frame_arenas: [2]heap.ArenaAllocator,

    stacks: Stacks,
    pop_flags: u64,

    chunks: chunk_pool.ChunkAllocator,

    const Stacks = TaggedLinkedList(union(enum) {
        parent: *Block,
        axis: Axis,
        color: [4]f32,
        width: Sizing,
        width_shrink: f32,
        height: Sizing,
        height_shrink: f32,
        flags: Block.Flags,
    });

    pub const Flags = Stacks.Tag;
    pub const Attribute = Stacks.Value;
    pub const Node = Stacks.Node;

    const PreOrderIterator = struct {
        node: ?*Block,

        pub fn next(self: *PreOrderIterator) ?*Block {
            const current = self.node orelse return null;
            self.node = nextPreOrder(current);
            return current;
        }

        fn nextPreOrder(current: *Block) ?*Block {
            if (current.children.first) |child| return child;

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

    pub fn init(self: *ViewState, gpa: Allocator) !void {
        self.* = .{
            .arena = .init(gpa),
            .root = null,
            .block_count = 0,
            .frame = 0,
            .frame_arenas = .{ .init(gpa), .init(gpa) },
            .stacks = .empty,
            .pop_flags = 0,
            .chunks = undefined,
        };

        const arena = self.arena.allocator();
        errdefer self.arena.deinit();

        try self.chunks.init(arena, &.{.{
            .capacity = 2048,
            .chunk_size = @sizeOf(Block),
        }});
    }

    pub fn deinit(self: *ViewState) void {
        for (self.frame_arenas) |arena| arena.deinit();
        self.arena.deinit();
    }

    pub fn begin(self: *ViewState, viewport: struct { width: f32, height: f32 }) !void {
        assert(viewport.width >= 0.0);
        assert(viewport.height >= 0.0);

        self.reset();
        errdefer self.reset();

        try self.nextAttrs(&.{
            .{ .width = .{ .fixed = viewport.width } },
            .{ .height = .{ .fixed = viewport.height } },
        });

        self.root = try self.block(.{});

        try self.pushAttr(.{ .parent = self.root.? });
    }

    pub fn finish(self: *ViewState) void {
        assert(self.root != null);

        layout(self);

        self.frame += 1;
        const arena_index = self.frame % self.frame_arenas.len;
        _ = self.frame_arenas[arena_index].reset(.retain_capacity);
    }

    pub fn block(self: *ViewState, flags: Block.Flags) !*Block {
        const new = try self.frameArena().create(Block);
        new.* = .empty;
        new.build(self, flags);

        self.block_count += 1;
        self.popFlagged();

        return new;
    }

    pub fn pushAttr(self: *ViewState, attr: Attribute) !void {
        const arena = self.frameArena();

        switch (attr) {
            inline else => |value, flag| {
                assert(self.pop_flags & stackFlag(flag) == 0);

                const node = try arena.create(Node(flag));
                node.* = .{ .value = value };
                self.stacks.prepend(flag, node);
            },
        }
    }

    pub fn popAttr(self: *ViewState, comptime flag: Flags) void {
        assert(self.pop_flags & stackFlag(flag) == 0);
        if (self.stacks.pop(flag) == null) unreachable;
    }

    pub fn nextAttr(self: *ViewState, attr: Attribute) !void {
        try self.pushAttr(attr);
        self.flagStack(meta.activeTag(attr));
    }

    pub fn pushAttrs(self: *ViewState, attrs: []const Attribute) !void {
        for (attrs) |attr| try self.pushAttr(attr);
    }

    pub fn popAttrs(self: *ViewState, comptime flags: []const Flags) void {
        inline for (flags) |flag| self.popAttr(flag);
    }

    pub fn nextAttrs(self: *ViewState, attrs: []const Attribute) !void {
        for (attrs) |attr| try self.nextAttr(attr);
    }

    pub fn preOrderIterator(self: *ViewState) PreOrderIterator {
        return .{ .node = self.root };
    }

    pub fn postOrderIterator(self: *ViewState) PostOrderIterator {
        return .{ .node = if (self.root) |root| firstPostOrder(root) else null };
    }

    fn frameArena(self: *ViewState) Allocator {
        return self.frame_arenas[self.frame % self.frame_arenas.len].allocator();
    }

    fn reset(self: *ViewState) void {
        self.root = null;
        self.stacks = .empty;
        self.pop_flags = 0;
        self.block_count = 0;
    }

    fn flagStack(self: *ViewState, flag: Flags) void {
        self.pop_flags |= stackFlag(flag);
    }

    fn popFlagged(self: *ViewState) void {
        inline for (@typeInfo(Stacks.Tag).@"enum".fields) |field| {
            const flag: Flags = @enumFromInt(field.value);
            if (self.pop_flags & stackFlag(flag) != 0) {
                self.pop_flags &= ~stackFlag(flag);
                if (self.stacks.pop(flag) == null) unreachable;
            }
        }
    }

    fn firstPostOrder(root: *Block) *Block {
        var node = root;
        while (node.children.first) |child| node = child;
        return node;
    }
};

const Axis = enum(u1) { x = 0, y = 1 };

const Sizing = union(enum) {
    pub const zero: Sizing = .{ .fixed = 0 };
    pub const grow: Sizing = .{ .percent = 1 };

    fit,
    fixed: f32,
    percent: f32,
};

const Block = struct {
    children: DoublyLinkedList(Block),
    child_count: u8,

    next: ?*Block,
    prev: ?*Block,
    parent: ?*Block,

    axis: Axis,
    sizing: [2]Sizing,
    shrink: [2]f32,
    color: [4]f32,
    flags: Flags,

    size: [2]f32,
    position: [2]f32,
    abs_position: [2]f32,
    bounds: [2]f32,

    const Flags = packed struct {
        const allowOverflow: Flags = .{ .overflow = 0b11 };

        overflow: u2 = 0,
    };

    const empty: Block = .{
        .children = .empty,
        .child_count = 0,
        .next = null,
        .prev = null,
        .parent = null,
        .axis = .x,
        .sizing = @splat(.zero),
        .shrink = @splat(1.0),
        .color = @splat(0.0),
        .flags = .{},
        .size = @splat(0.0),
        .position = @splat(0.0),
        .abs_position = @splat(0.0),
        .bounds = @splat(0.0),
    };

    fn build(self: *Block, state: *ViewState, flags: Flags) void {
        if (state.stacks.get(.parent).head) |parent| {
            parent.value.child_count += 1;
            parent.value.children.append(self);
            self.parent = parent.value;
        }

        if (state.stacks.get(.axis).head) |node| self.axis = node.value;
        if (state.stacks.get(.color).head) |node| self.color = node.value;
        if (state.stacks.get(.width).head) |node| self.sizing[0] = node.value;
        if (state.stacks.get(.height).head) |node| self.sizing[1] = node.value;
        if (state.stacks.get(.width_shrink).head) |node| self.shrink[0] = clamp(node.value, 0.0, 1.0);
        if (state.stacks.get(.height_shrink).head) |node| self.shrink[1] = clamp(node.value, 0.0, 1.0);

        const stack_flags: u2 = if (state.stacks.get(.flags).head) |node| @bitCast(node.value) else 0;
        self.flags = @bitCast(@as(u2, @bitCast(flags)) | stack_flags);
    }
};

fn stackFlag(flag: ViewState.Flags) u64 {
    return @as(u64, 1) << @intFromEnum(flag);
}

fn layout(state: *ViewState) void {
    assert(state.root != null);

    inline for (@typeInfo(Axis).@"enum".fields) |field| {
        const axis = field.value;

        {
            var iterator = state.preOrderIterator();
            while (iterator.next()) |block| {
                switch (block.sizing[axis]) {
                    .fixed => |size| block.size[axis] = size,
                    .percent => |percent| {
                        const parent_size = parent_size: {
                            var node = block.parent;
                            while (node) |parent| : (node = parent.parent) {
                                switch (parent.sizing[axis]) {
                                    .fixed, .percent => break :parent_size parent.size[axis],
                                    else => {},
                                }
                            }

                            break :parent_size 0.0;
                        };

                        block.size[axis] = parent_size * percent;
                    },
                    else => {},
                }
            }
        }

        {
            var iterator = state.postOrderIterator();
            while (iterator.next()) |block| {
                switch (block.sizing[axis]) {
                    .fit => {
                        var total: f32 = 0.0;
                        var children = block.children.first;
                        while (children) |child| : (children = child.next) {
                            if (@intFromEnum(block.axis) == axis) {
                                total += child.size[axis];
                            } else {
                                total = @max(total, child.size[axis]);
                            }
                        }

                        block.size[axis] = total;
                    },
                    else => {},
                }
            }
        }

        {
            var iterator = state.preOrderIterator();
            while (iterator.next()) |block| {
                const allowed = block.size[axis];
                const overflow_mask = @as(u2, 1) << axis;

                if (@intFromEnum(block.axis) != axis and
                    block.flags.overflow & overflow_mask == 0)
                {
                    var children = block.children.first;
                    while (children) |child| : (children = child.next) {
                        const size = child.size[axis];
                        const overflow = size - allowed;
                        const fix = clamp(overflow, 0, size);
                        if (fix > 0) child.size[axis] -= fix;
                    }
                }

                if (@intFromEnum(block.axis) == axis and
                    block.flags.overflow & overflow_mask == 0)
                {
                    var used: f32 = 0.0;
                    var available: f32 = 0.0;

                    var children = block.children.first;
                    while (children) |child| : (children = child.next) {
                        used += child.size[axis];
                        available += child.size[axis] * (1.0 - child.shrink[axis]);
                    }

                    const overflow = used - allowed;

                    if (overflow > 0 and available > 0) {
                        children = block.children.first;

                        while (children) |child| : (children = child.next) {
                            child.size[axis] -= child.size[axis] *
                                (1.0 - child.shrink[axis]) *
                                clamp(overflow / available, 0, 1);
                        }
                    }
                }

                if (block.flags.overflow & overflow_mask != 0) {
                    var children = block.children.first;
                    while (children) |child| : (children = child.next) {
                        switch (child.sizing[axis]) {
                            .percent => |percent| {
                                child.size[axis] = block.size[axis] * percent;
                            },
                            else => {},
                        }
                    }
                }
            }
        }

        {
            var iterator = state.preOrderIterator();
            while (iterator.next()) |block| {
                var position: f32 = 0.0;
                var bounds: f32 = 0.0;

                var children = block.children.first;
                while (children) |child| : (children = child.next) {
                    child.position[axis] = position;

                    if (@intFromEnum(block.axis) == axis) {
                        position += child.size[axis];
                        bounds += child.size[axis];
                    } else {
                        bounds = @max(bounds, child.size[axis]);
                    }

                    child.abs_position[axis] = block.abs_position[axis] + child.position[axis];
                }

                block.bounds[axis] = bounds;
            }
        }
    }
}

test "view state builds blocks and applies stacked attributes" {
    var state: ViewState = undefined;
    try state.init(testing.allocator);
    defer state.deinit();

    try state.begin(.{ .width = 600, .height = 800 });

    const color = [4]f32{ 1.0, 0.5, 0.25, 1.0 };
    try state.nextAttrs(&.{
        .{ .axis = .y },
        .{ .color = color },
    });
    const styled = try state.block(.{});

    try testing.expectEqual(Axis.y, styled.axis);
    try testing.expectEqual(color, styled.color);
    try testing.expect(state.stacks.get(.axis).is_empty());
    try testing.expect(state.stacks.get(.color).is_empty());

    try state.pushAttr(.{ .axis = .x });
    state.popAttr(.axis);
    state.finish();

    try testing.expectEqual(@as(u64, 2), state.block_count);
    try testing.expectEqual(styled, state.root.?.children.last);
}

test "fixed layout preserves overflow when requested" {
    var state: ViewState = undefined;
    try state.init(testing.allocator);
    defer state.deinit();

    try state.begin(.{ .width = 600, .height = 800 });
    try state.pushAttr(.{ .flags = .allowOverflow });

    try state.nextAttrs(&.{ .{ .width = .grow }, .{ .height = .grow } });
    const wrapper = try state.block(.{});
    try state.pushAttr(.{ .parent = wrapper });

    try state.nextAttrs(&.{ .{ .width = .{ .fixed = 800 } }, .{ .height = .{ .fixed = 900 } } });
    const first = try state.block(.{});
    try state.nextAttrs(&.{ .{ .width = .{ .fixed = 120 } }, .{ .height = .{ .fixed = 120 } } });
    const second = try state.block(.{});

    state.popAttr(.parent);
    state.popAttr(.flags);
    state.finish();

    try testing.expectEqual([2]f32{ 800, 900 }, first.size);
    try testing.expectEqual([2]f32{ 120, 120 }, second.size);
    try testing.expectEqual([2]f32{ 800, 0 }, second.position);
    try testing.expectEqual([2]f32{ 920, 900 }, wrapper.bounds);
}

test "percent sizing shrinks when siblings overflow" {
    var state: ViewState = undefined;
    try state.init(testing.allocator);
    defer state.deinit();

    try state.begin(.{ .width = 600, .height = 800 });
    try state.nextAttrs(&.{ .{ .width = .grow }, .{ .height = .grow } });
    const parent = try state.block(.{});
    try state.pushAttr(.{ .parent = parent });

    try state.nextAttrs(&.{
        .{ .width = .{ .fixed = 100 } },
        .{ .height = .grow },
    });
    const first = try state.block(.{});

    try state.nextAttrs(&.{
        .{ .width = .grow },
        .{ .height = .grow },
        .{ .width_shrink = 0.0 },
    });
    const middle = try state.block(.{});

    try state.nextAttrs(&.{
        .{ .width = .{ .fixed = 100 } },
        .{ .height = .grow },
    });
    const last = try state.block(.{});

    state.popAttr(.parent);
    state.finish();

    try testing.expectEqual([2]f32{ 100, 800 }, first.size);
    try testing.expectEqual([2]f32{ 400, 800 }, middle.size);
    try testing.expectEqual([2]f32{ 100, 800 }, last.size);
    try testing.expectEqual([2]f32{ 100, 0 }, middle.position);
    try testing.expectEqual([2]f32{ 500, 0 }, last.position);
}

test "grow is full parent percentage" {
    var state: ViewState = undefined;
    try state.init(testing.allocator);
    defer state.deinit();

    try state.begin(.{ .width = 600, .height = 800 });
    try state.nextAttrs(&.{ .{ .width = .{ .fixed = 400 } }, .{ .height = .{ .fixed = 300 } } });
    const parent = try state.block(.{});
    try state.pushAttr(.{ .parent = parent });

    try state.nextAttrs(&.{ .{ .width = .{ .percent = 0.5 } }, .{ .height = .grow } });
    const child = try state.block(.{});
    state.popAttr(.parent);
    state.finish();

    try testing.expectEqual([2]f32{ 200, 300 }, child.size);
}

test "fit sizing resolves from descendants" {
    var state: ViewState = undefined;
    try state.init(testing.allocator);
    defer state.deinit();

    try state.begin(.{ .width = 600, .height = 800 });
    try state.nextAttrs(&.{ .{ .width = .fit }, .{ .height = .fit }, .{ .axis = .y } });
    const parent = try state.block(.{});
    try state.pushAttr(.{ .parent = parent });

    try state.nextAttrs(&.{ .{ .width = .fit }, .{ .height = .fit } });
    const first = try state.block(.{});
    try state.pushAttr(.{ .parent = first });

    try state.nextAttrs(&.{ .{ .width = .{ .fixed = 100 } }, .{ .height = .{ .fixed = 150 } } });
    _ = try state.block(.{});
    try state.nextAttrs(&.{ .{ .width = .{ .fixed = 100 } }, .{ .height = .{ .fixed = 150 } } });
    _ = try state.block(.{});
    state.popAttr(.parent);

    try state.nextAttrs(&.{ .{ .width = .{ .fixed = 400 } }, .{ .height = .{ .fixed = 450 } } });
    const second = try state.block(.{});
    state.popAttr(.parent);
    state.finish();

    try testing.expectEqual([2]f32{ 200, 150 }, first.size);
    try testing.expectEqual([2]f32{ 400, 600 }, parent.size);
    try testing.expectEqual([2]f32{ 0, 150 }, second.position);
}
