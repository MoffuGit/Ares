// The immediate-mode GUI implementation is based on concepts from Digital Grove (https://www.dgtlgrove.com/).

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const clamp = std.math.clamp;
const heap = std.heap;
const meta = std.meta;
const testing = std.testing;
const Wyhash = std.hash.Wyhash;
const win = @import("window.zig");
const Window = win.Window;

const chunk_pool = @import("chunk_pool.zig");
const datastruct = @import("datastruct.zig");
const DoublyLinkedList = datastruct.DoublyLinkedList;
const TaggedLinkedList = datastruct.TaggedLinkedList;

const log = std.log.scoped(.view);

pub const ViewState = struct {
    arena: heap.ArenaAllocator,
    root: ?*Block,
    block_count: u64,

    mouse: [2]f32,

    frame: u64,
    frame_arenas: [2]heap.ArenaAllocator,

    stacks: Stacks,
    pop_flags: u64,

    cache: []DoublyLinkedList(Cache),

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

    fn stackFlag(flag: Flags) u64 {
        return @as(u64, 1) << @intFromEnum(flag);
    }

    pub fn init(self: *ViewState, gpa: Allocator) !void {
        self.* = .{
            .mouse = @splat(0.0),
            .cache = undefined,
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

        self.cache = try arena.alloc(DoublyLinkedList(Cache), 2048);
        @memset(self.cache, .empty);

        try self.chunks.init(arena, &.{.{ .capacity = 2048, .chunk_size = @sizeOf(Block) }});
    }

    pub fn deinit(self: *ViewState) void {
        for (self.frame_arenas) |arena| arena.deinit();
        self.arena.deinit();
    }

    pub fn begin(self: *ViewState, window: Window) !void {
        self.reset();
        errdefer self.reset();

        const size = try window.size();
        const mouse = try window.mouse();

        self.mouse = .{ mouse.x, mouse.y };

        try self.nextAttrs(&.{
            .{ .width = .{ .fixed = size.w } },
            .{ .height = .{ .fixed = size.h } },
        });

        self.root = try self.buildBlock(.{}, null);

        try self.pushAttr(.{ .parent = self.root.? });
    }

    pub fn finish(self: *ViewState) void {
        const root = self.root orelse unreachable;

        inline for (0..2) |axis| {
            root.layout(axis);
        }

        for (self.cache) |*list| {
            var entry: ?*Cache = list.first;
            while (entry) |cache| {
                entry = cache.next;
                const cached: *Block = @fieldParentPtr("cache", cache);

                if (cached.touched_frame != self.frame) {
                    list.remove(cache);
                    self.chunks.allocator().destroy(cached);
                }
            }
        }

        self.frame += 1;

        const arena_index = self.frame % self.frame_arenas.len;
        _ = self.frame_arenas[arena_index].reset(.retain_capacity);
    }

    pub fn signalForBlock(self: *ViewState, block: *Block) Signals {
        const flags = block.flags;

        var signal: Signals = .none;

        const mouse = self.mouse;
        const rect = block.rect;

        if (rect[0][0] <= mouse[0] and mouse[0] < rect[1][0] and
            rect[0][1] <= mouse[1] and mouse[1] < rect[1][1])
        {
            signal.mouseover = true;
        }

        if (flags.mouse and rect[0][0] <= mouse[0] and mouse[0] < rect[1][0] and
            rect[0][1] <= mouse[1] and mouse[1] < rect[1][1])
        {
            signal.hovered = true;
        }

        return signal;
    }

    pub fn fmt(self: *ViewState, comptime format: []const u8, args: anytype) ![]u8 {
        const required = std.fmt.count(format, args);
        const frame_arena = self.frameArena();
        const buffer = try frame_arena.alloc(u8, required);
        return std.fmt.bufPrint(buffer, format, args) catch unreachable;
    }

    pub fn blockFromFmt(self: *ViewState, comptime format: []const u8, args: anytype, flags: Block.Flags) !*Block {
        const string = try self.fmt(format, args);

        return try self.blockFromString(string, flags);
    }

    pub fn blockFromString(self: *ViewState, string: []const u8, flags: Block.Flags) !*Block {
        const chunk = if (std.mem.find(u8, string, "@@@")) |index|
            string[index + "@@@".len ..]
        else
            "";

        const key: ?u64 = if (chunk.len == 0) null else key: {
            var node = self.stacks.get(.parent).head;
            while (node) |current| : (node = current.next) {
                if (current.value.key) |parent_key| break :key Wyhash.hash(parent_key, chunk);
            }

            break :key Wyhash.hash(0, chunk);
        };

        return try self.buildBlock(flags, key);
    }

    pub fn getBlock(self: *ViewState, key: u64) ?*Block {
        const list = &self.cache[key % self.cache.len];
        var entry = list.first;

        while (entry) |cache| : (entry = cache.next) {
            const block: *Block = @fieldParentPtr("cache", cache);
            if (block.key == key) {
                return block;
            }
        }

        return null;
    }

    pub fn cacheBlock(self: *ViewState, block: *Block, key: u64) void {
        const list = &self.cache[key % self.cache.len];

        block.key = key;

        list.append(&block.cache);
    }

    pub fn buildBlock(self: *ViewState, flags: Block.Flags, optional_key: ?u64) !*Block {
        const block = bkl: {
            if (optional_key) |key| {
                if (self.getBlock(key)) |cached| {
                    if (cached.touched_frame == self.frame) {
                        const block = try self.frameArena().create(Block);
                        block.* = .empty;

                        break :bkl block;
                    }

                    cached.reset();

                    break :bkl cached;
                } else {
                    const chunks = self.chunks.allocator();

                    const block = try chunks.create(Block);
                    block.* = .empty;

                    self.cacheBlock(block, key);

                    break :bkl block;
                }
            } else {
                const block = try self.frameArena().create(Block);
                block.* = .empty;

                break :bkl block;
            }
        };

        block.build(self, flags);

        return block;
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
};

const Cache = struct {
    pub const _null: Cache = .{
        .next = null,
        .prev = null,
    };
    next: ?*Cache,
    prev: ?*Cache,
};

pub const Axis = enum(u1) { x = 0, y = 1 };

pub const Sizing = union(enum) {
    pub const none: Sizing = .{ .fixed = 0 };
    pub const grow: Sizing = .{ .percent = 1 };

    fit,
    fixed: f32,
    percent: f32,
};

pub const Signals = packed struct {
    const none: Signals = .{
        .hovered = false,
        .mouseover = false,
    };

    hovered: bool,
    mouseover: bool,
};

pub const Block = struct {
    children: DoublyLinkedList(Block),
    child_count: u8,

    next: ?*Block,
    prev: ?*Block,
    parent: ?*Block,

    key: ?u64,
    cache: Cache,
    touched_frame: u64,

    axis: Axis,
    sizing: [2]Sizing,
    shrink: [2]f32,
    color: [4]f32,
    flags: Flags,

    size: [2]f32,
    position: [2]f32,
    rect: [2][2]f32,
    bounds: [2]f32,

    pub const Flags = packed struct {
        pub const allowOverflow: Flags = .{ .overflow = 0b11 };

        overflow: u2 = 0,
        mouse: bool = false,
    };

    pub const empty: Block = .{
        .rect = @splat(@splat(0.0)),
        .cache = ._null,
        .children = .empty,
        .child_count = 0,
        .next = null,
        .prev = null,
        .parent = null,
        .axis = .x,
        .touched_frame = 0,
        .sizing = @splat(.none),
        .shrink = @splat(1.0),
        .color = @splat(0.0),
        .flags = .{},
        .size = @splat(0.0),
        .position = @splat(0.0),
        .bounds = @splat(0.0),
        .key = null,
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

        const stack_flags: u3 = if (state.stacks.get(.flags).head) |node| @bitCast(node.value) else 0;
        self.flags = @bitCast(@as(u3, @bitCast(flags)) | stack_flags);

        self.touched_frame = state.frame;

        state.block_count += 1;
        state.popFlagged();
    }

    pub fn reset(self: *Block) void {
        self.children = .empty;
        self.child_count = 0;
        self.next = null;
        self.prev = null;
        self.parent = null;

        self.axis = .x;
        self.sizing = @splat(.none);
        self.shrink = @splat(1.0);
        self.color = @splat(0.0);
        self.flags = .{};
    }

    pub fn nextPreOrder(self: *Block) ?*Block {
        if (self.children.first) |child| return child;

        var ancestor = self;
        while (true) {
            if (ancestor.next) |sibling| return sibling;
            ancestor = ancestor.parent orelse return null;
        }
    }

    pub fn firstPostOrder(self: *Block) *Block {
        var block = self;
        while (block.children.first) |child| block = child;
        return block;
    }

    pub fn nextPostOrder(self: *Block) ?*Block {
        const parent = self.parent orelse return null;
        return if (self.next) |sibling| sibling.firstPostOrder() else parent;
    }

    pub fn layout(self: *Block, axis: u1) void {
        self.resolveFixedSizing(axis);
        self.resolvePerSizing(axis);
        self.resolveFitSizing(axis);
        self.resolveOverflow(axis);
        self.resolveRect(axis);
    }

    pub fn resolveFixedSizing(self: *Block, axis: u1) void {
        var block: ?*Block = self;
        while (block) |current| : (block = current.nextPreOrder()) {
            switch (current.sizing[axis]) {
                .fixed => |fixed| current.size[axis] = fixed,
                else => {},
            }
        }
    }

    pub fn resolvePerSizing(self: *Block, axis: u1) void {
        var block: ?*Block = self;
        while (block) |current| : (block = current.nextPreOrder()) {
            switch (current.sizing[axis]) {
                .percent => |percent| {
                    const parent_size = parent_size: {
                        var node = current.parent;
                        while (node) |parent| : (node = parent.parent) {
                            switch (parent.sizing[axis]) {
                                .fixed, .percent => break :parent_size parent.size[axis],
                                else => {},
                            }
                        }

                        break :parent_size 0.0;
                    };

                    current.size[axis] = parent_size * percent;
                },
                else => {},
            }
        }
    }

    pub fn resolveFitSizing(self: *Block, axis: u1) void {
        var block: ?*Block = self.firstPostOrder();
        while (block) |current| : (block = current.nextPostOrder()) {
            switch (current.sizing[axis]) {
                .fit => {
                    var total: f32 = 0.0;
                    var children = current.children.first;
                    while (children) |child| : (children = child.next) {
                        if (@intFromEnum(current.axis) == axis) {
                            total += child.size[axis];
                        } else {
                            total = @max(total, child.size[axis]);
                        }
                    }

                    current.size[axis] = total;
                },
                else => {},
            }
        }
    }

    pub fn resolveOverflow(self: *Block, axis: u1) void {
        var block: ?*Block = self;
        while (block) |current| : (block = current.nextPreOrder()) {
            const allowed = current.size[axis];
            const overflow_mask = @as(u2, 1) << axis;

            if (@intFromEnum(current.axis) != axis and
                current.flags.overflow & overflow_mask == 0)
            {
                var children = current.children.first;
                while (children) |child| : (children = child.next) {
                    const size = child.size[axis];
                    const overflow = size - allowed;
                    const fix = clamp(overflow, 0, size);
                    if (fix > 0) child.size[axis] -= fix;
                }
            }

            if (@intFromEnum(current.axis) == axis and
                current.flags.overflow & overflow_mask == 0)
            {
                var used: f32 = 0.0;
                var available: f32 = 0.0;

                var children = current.children.first;
                while (children) |child| : (children = child.next) {
                    used += child.size[axis];
                    available += child.size[axis] * (1.0 - child.shrink[axis]);
                }

                const overflow = used - allowed;

                if (overflow > 0 and available > 0) {
                    children = current.children.first;

                    while (children) |child| : (children = child.next) {
                        child.size[axis] -= child.size[axis] *
                            (1.0 - child.shrink[axis]) *
                            clamp(overflow / available, 0, 1);
                    }
                }
            }

            if (current.flags.overflow & overflow_mask != 0) {
                var children = current.children.first;
                while (children) |child| : (children = child.next) {
                    switch (child.sizing[axis]) {
                        .percent => |percent| {
                            child.size[axis] = current.size[axis] * percent;
                        },
                        else => {},
                    }
                }
            }
        }
    }

    pub fn resolveRect(self: *Block, axis: u1) void {
        var block: ?*Block = self;
        while (block) |current| : (block = current.nextPreOrder()) {
            var position: f32 = 0.0;
            var bounds: f32 = 0.0;

            var children = current.children.first;
            while (children) |child| : (children = child.next) {
                child.position[axis] = position;

                if (@intFromEnum(current.axis) == axis) {
                    position += child.size[axis];
                    bounds += child.size[axis];
                } else {
                    bounds = @max(bounds, child.size[axis]);
                }

                child.rect[0][axis] = current.rect[0][axis] + child.position[axis];
                child.rect[1][axis] = child.rect[0][axis] + child.size[axis];

                for (0..2) |p| {
                    child.rect[p][axis] = @floor(child.rect[p][axis]);
                }
            }

            current.bounds[axis] = bounds;
        }
    }
};

test "Basic Operations" {
    const window: Window = .{};
    var state: ViewState = undefined;
    try state.init(testing.allocator);
    defer state.deinit();

    const key: u64 = 42;
    const cache = &state.cache[key % state.cache.len];

    try state.begin(window);
    try state.nextAttr(.{ .width = .{ .fixed = 10 } });
    _ = try state.buildBlock(.{}, null);
    try state.nextAttr(.{ .width = .{ .fixed = 40 } });
    const first = try state.buildBlock(.{}, key);
    try state.pushAttr(.{ .parent = first });
    _ = try state.buildBlock(.{}, null);
    state.popAttr(.parent);
    state.finish();

    try testing.expectEqual(@as(usize, 1), cache.len());
    try testing.expectEqual([2]f32{ 40, 0 }, first.size);
    try testing.expectEqual([2]f32{ 10, 0 }, first.position);
    try testing.expectEqual(@as(u8, 1), first.child_count);

    try state.begin(window);
    try state.nextAttrs(&.{
        .{ .axis = .y },
        .{ .width = .{ .fixed = 50 } },
    });
    const second = try state.buildBlock(.{}, key);

    try testing.expectEqual(first, second);
    try testing.expectEqual([2]f32{ 40, 0 }, second.size);
    try testing.expectEqual([2]f32{ 10, 0 }, second.position);
    try testing.expectEqual(Axis.y, second.axis);
    try testing.expectEqual(Sizing{ .fixed = 50 }, second.sizing[0]);
    try testing.expect(second.children.is_empty());
    try testing.expectEqual(@as(u8, 0), second.child_count);
    state.finish();

    try testing.expectEqual(@as(usize, 1), cache.len());

    try state.begin(window);
    state.finish();

    try testing.expect(cache.is_empty());
}

test "Hash Block" {
    const window: Window = .{};
    var state: ViewState = undefined;
    try state.init(testing.allocator);
    defer state.deinit();

    try state.begin(window);
    _ = try state.blockFromString("First label@@@identity", .{});
    const first = state.root.?.children.last.?;
    try testing.expectEqual(Wyhash.hash(0, "identity"), first.key.?);
    state.finish();

    try state.begin(window);
    _ = try state.blockFromString("Different label@@@identity", .{});
    const second = state.root.?.children.last.?;
    try testing.expectEqual(first, second);
    state.finish();

    try state.begin(window);
    _ = try state.blockFromString("No identity@@@", .{});
    try testing.expectEqual(null, state.root.?.children.last.?.key);
    state.finish();

    try state.begin(window);
    _ = try state.blockFromString("No marker", .{});
    try testing.expectEqual(null, state.root.?.children.last.?.key);
    state.finish();
}

test "Fixed Layout" {
    const window: Window = .{};
    var state: ViewState = undefined;
    try state.init(testing.allocator);
    defer state.deinit();

    try state.begin(window);
    try state.pushAttr(.{ .flags = .allowOverflow });

    try state.nextAttrs(&.{ .{ .width = .grow }, .{ .height = .grow } });
    const wrapper = try state.buildBlock(.{}, null);
    try state.pushAttr(.{ .parent = wrapper });

    try state.nextAttrs(&.{ .{ .width = .{ .fixed = 800 } }, .{ .height = .{ .fixed = 900 } } });
    const first = try state.buildBlock(.{}, null);
    try state.nextAttrs(&.{ .{ .width = .{ .fixed = 120 } }, .{ .height = .{ .fixed = 120 } } });
    const second = try state.buildBlock(.{}, null);

    state.popAttr(.parent);
    state.popAttr(.flags);
    state.finish();

    try testing.expectEqual([2]f32{ 800, 900 }, first.size);
    try testing.expectEqual([2]f32{ 120, 120 }, second.size);
    try testing.expectEqual([2]f32{ 800, 0 }, second.position);
    try testing.expectEqual([2]f32{ 920, 900 }, wrapper.bounds);
}

test "Percent Layout" {
    const window: Window = .{};
    var state: ViewState = undefined;
    try state.init(testing.allocator);
    defer state.deinit();

    try state.begin(window);
    try state.nextAttrs(&.{ .{ .width = .grow }, .{ .height = .grow } });
    const parent = try state.buildBlock(.{}, null);
    try state.pushAttr(.{ .parent = parent });

    try state.nextAttrs(&.{
        .{ .width = .{ .fixed = 100 } },
        .{ .height = .grow },
    });
    const first = try state.buildBlock(.{}, null);

    try state.nextAttrs(&.{
        .{ .width = .grow },
        .{ .height = .grow },
        .{ .width_shrink = 0.0 },
    });
    const middle = try state.buildBlock(.{}, null);

    try state.nextAttrs(&.{
        .{ .width = .{ .fixed = 100 } },
        .{ .height = .grow },
    });
    const last = try state.buildBlock(.{}, null);

    state.popAttr(.parent);
    state.finish();

    try testing.expectEqual([2]f32{ 100, 800 }, first.size);
    try testing.expectEqual([2]f32{ 400, 800 }, middle.size);
    try testing.expectEqual([2]f32{ 100, 800 }, last.size);
    try testing.expectEqual([2]f32{ 100, 0 }, middle.position);
    try testing.expectEqual([2]f32{ 500, 0 }, last.position);
}

test "Grow Layout" {
    const window: Window = .{};

    var state: ViewState = undefined;
    try state.init(testing.allocator);
    defer state.deinit();

    try state.begin(window);
    try state.nextAttrs(&.{ .{ .width = .{ .fixed = 400 } }, .{ .height = .{ .fixed = 300 } } });
    const parent = try state.buildBlock(.{}, null);
    try state.pushAttr(.{ .parent = parent });

    try state.nextAttrs(&.{ .{ .width = .{ .percent = 0.5 } }, .{ .height = .grow } });
    const child = try state.buildBlock(.{}, null);
    state.popAttr(.parent);
    state.finish();

    try testing.expectEqual([2]f32{ 200, 300 }, child.size);
}

test "fit sizing resolves from descendants" {
    const window: Window = .{};

    var state: ViewState = undefined;
    try state.init(testing.allocator);
    defer state.deinit();

    try state.begin(window);
    try state.nextAttrs(&.{ .{ .width = .fit }, .{ .height = .fit }, .{ .axis = .y } });
    const parent = try state.buildBlock(.{}, null);
    try state.pushAttr(.{ .parent = parent });

    try state.nextAttrs(&.{ .{ .width = .fit }, .{ .height = .fit } });
    const first = try state.buildBlock(.{}, null);
    try state.pushAttr(.{ .parent = first });

    try state.nextAttrs(&.{ .{ .width = .{ .fixed = 100 } }, .{ .height = .{ .fixed = 150 } } });
    _ = try state.buildBlock(.{}, null);
    try state.nextAttrs(&.{ .{ .width = .{ .fixed = 100 } }, .{ .height = .{ .fixed = 150 } } });
    _ = try state.buildBlock(.{}, null);
    state.popAttr(.parent);

    try state.nextAttrs(&.{ .{ .width = .{ .fixed = 400 } }, .{ .height = .{ .fixed = 450 } } });
    const second = try state.buildBlock(.{}, null);
    state.popAttr(.parent);
    state.finish();

    try testing.expectEqual([2]f32{ 200, 150 }, first.size);
    try testing.expectEqual([2]f32{ 400, 600 }, parent.size);
    try testing.expectEqual([2]f32{ 0, 150 }, second.position);
}
