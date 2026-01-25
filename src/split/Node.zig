const std = @import("std");
const Allocator = std.mem.Allocator;

const NodePath = @import("mod.zig").NodePath;
const Element = @import("../element/mod.zig").Element;
const Buffer = @import("../Buffer.zig");
const HitGrid = @import("../HitGrid.zig");
const EventContext = @import("../events/EventContext.zig");
const vaxis = @import("vaxis");

pub const Direction = enum {
    horizontal,
    vertical,
};

pub const Split = struct {
    direction: Direction,
    children: std.ArrayList(*Node) = .{},
    equal_nodes: std.ArrayList(*Node) = .{},
    alloc: Allocator,
    ratio: f32 = 1.0,
    equal: bool = false,
    element: Element,

    pub fn create(alloc: Allocator, direction: Direction) !*Split {
        const self = try alloc.create(Split);
        self.* = .{
            .direction = direction,
            .alloc = alloc,
            .element = Element.init(alloc, .{
                .style = .{
                    .flex_direction = switch (direction) {
                        .horizontal => .column,
                        .vertical => .row,
                    },
                    .gap = switch (direction) {
                        .horizontal => .{ .column = .{ .point = 1 } },
                        .vertical => .{ .row = .{ .point = 1 } },
                    },
                },
            }),
        };
        return self;
    }

    pub fn destroy(self: *Split) void {
        for (self.children.items) |child| {
            child.destroy();
            self.alloc.destroy(child);
        }
        self.children.deinit(self.alloc);
        self.equal_nodes.deinit(self.alloc);
        self.element.deinit();
        self.alloc.destroy(self);
    }

    pub fn addChild(self: *Split, node: *Node) !void {
        try self.children.append(self.alloc, node);
        try self.element.addChild(node.getElement());
        if (node.isEqual()) {
            try self.equal_nodes.append(self.alloc, node);
        }
        self.updateEqualRatios();
    }

    pub fn insertChild(self: *Split, index: usize, node: *Node) !void {
        try self.children.insert(self.alloc, index, node);
        try self.element.addChild(node.getElement());
        if (node.isEqual()) {
            try self.equal_nodes.append(self.alloc, node);
        }
        self.updateEqualRatios();
    }

    pub fn get(self: *Split, index: usize) !*Node {
        if (index >= self.children.items.len) return error.OutOfBounds;
        return self.children.items[index];
    }

    pub fn removeChild(self: *Split, index: usize) *Node {
        const removed = self.children.orderedRemove(index);
        self.element.removeChild(removed.getElement().num);
        if (removed.isEqual()) {
            for (self.equal_nodes.items, 0..) |node, i| {
                if (node == removed) {
                    _ = self.equal_nodes.orderedRemove(i);
                    break;
                }
            }
        }
        self.updateEqualRatios();
        return removed;
    }

    pub fn childCount(self: *const Split) usize {
        return self.children.items.len;
    }

    pub fn updateEqualRatios(self: *Split) void {
        const count = self.children.items.len;
        if (count == 0) return;
        const equal_ratio = 1.0 / @as(f32, @floatFromInt(count));
        for (self.equal_nodes.items) |node| {
            node.setRatioInternal(equal_ratio);
        }
    }

    pub fn registerEqualNode(self: *Split, node: *Node) !void {
        for (self.equal_nodes.items) |n| {
            if (n == node) return;
        }
        try self.equal_nodes.append(self.alloc, node);
        self.updateEqualRatios();
    }

    pub fn unregisterEqualNode(self: *Split, node: *Node) void {
        for (self.equal_nodes.items, 0..) |n, i| {
            if (n == node) {
                _ = self.equal_nodes.orderedRemove(i);
                break;
            }
        }
    }
};

pub const View = struct {
    id: u64,
    ratio: f32 = 1.0,
    equal: bool = false,
    alloc: Allocator,
    element: Element,
    focus: bool = false,

    fn draw(element: *Element, buffer: *Buffer) void {
        const self: *View = @ptrCast(@alignCast(element.userdata));

        const x = element.layout.left;
        const y = element.layout.top;

        const cell: vaxis.Cell = if (!self.focus) .{
            .style = .{ .bg = .{ .rgb = .{ 0, 255, 0 } } },
        } else .{
            .style = .{ .bg = .{ .rgb = .{ 255, 0, 255 } } },
        };

        var row: u16 = 0;
        while (row < element.layout.height) : (row += 1) {
            var col: u16 = 0;
            while (col < element.layout.width) : (col += 1) {
                const px = x + col;
                const py = y + row;
                if (px < buffer.width and py < buffer.height) {
                    buffer.writeCell(px, py, cell);
                }
            }
        }
    }

    fn hit(element: *Element, hit_grid: *HitGrid) void {
        const x = element.layout.left;
        const y = element.layout.top;

        hit_grid.fillRect(x, y, element.layout.width, element.layout.height, element.num);
    }

    fn onClick(element: *Element, ctx: *EventContext, mouse: vaxis.Mouse) void {
        _ = ctx;
        if (mouse.button == .left) {
            element.context.?.setFocus(element);
        }
    }

    fn onFocus(element: *Element) void {
        const self: *View = @ptrCast(@alignCast(element.userdata));
        self.focus = true;
        element.context.?.requestDraw();
    }

    fn onBlur(element: *Element) void {
        const self: *View = @ptrCast(@alignCast(element.userdata));
        self.focus = false;
        element.context.?.requestDraw();
    }

    pub fn create(alloc: Allocator, id: u64) !*View {
        const self = try alloc.create(View);
        self.* = .{
            .id = id,
            .alloc = alloc,
            .element = Element.init(alloc, .{
                .userdata = self,
                .drawFn = draw,
                .hitGridFn = hit,
                .focusFn = onFocus,
                .blurFn = onBlur,
                .clickFn = onClick,
                .style = .{
                    .flex_grow = 1.0,
                },
            }),
        };
        return self;
    }

    pub fn destroy(self: *View) void {
        self.element.deinit();
        self.alloc.destroy(self);
    }
};

pub const Node = union(enum) {
    split: *Split,
    view: *View,

    pub fn destroy(self: *Node) void {
        switch (self.*) {
            .split => |s| s.destroy(),
            .view => |v| v.destroy(),
        }
    }

    pub fn getElement(self: *Node) *Element {
        switch (self.*) {
            .split => |s| return &s.element,
            .view => |v| return &v.element,
        }
    }

    pub fn find(node: *Node, id: u64) ?*Node {
        switch (node.*) {
            .view => |v| {
                if (v.id == id) return node;
            },
            .split => |s| {
                for (s.children.items) |child| {
                    if (child.find(id)) |found| {
                        return found;
                    }
                }
            },
        }

        return null;
    }

    pub fn path(self: *Node, alloc: Allocator, to: u64) ?NodePath {
        var _path = NodePath{};
        if (self.findPath(alloc, to, &_path)) return _path;

        _path.deinit(alloc);
        return null;
    }

    pub fn findPath(self: *Node, alloc: Allocator, id: u64, _path: *NodePath) bool {
        switch (self.*) {
            .view => |v| {
                return v.id == id;
            },
            .split => |s| {
                for (s.children.items, 0..) |child, i| {
                    _path.append(alloc, i) catch return false;
                    if (child.findPath(alloc, id, _path)) return true;
                    _ = _path.pop();
                }
            },
        }
        return false;
    }

    pub fn ratio(self: *Node) f32 {
        switch (self.*) {
            .split => |split| return split.ratio,
            .view => |view| return view.ratio,
        }
    }

    pub fn setRatio(self: *Node, r: f32) void {
        self.setRatioInternal(r);
        switch (self.*) {
            .split => |split| split.equal = false,
            .view => |view| view.equal = false,
        }
    }

    pub fn setRatioInternal(self: *Node, r: f32) void {
        switch (self.*) {
            .split => |split| {
                split.ratio = r;
                split.element.style.flex_grow = r;
                split.element.style.apply(split.element.node);
            },
            .view => |view| {
                view.ratio = r;
                view.element.style.flex_grow = r;
                view.element.style.apply(view.element.node);
            },
        }
    }

    pub fn isEqual(self: *Node) bool {
        switch (self.*) {
            .split => |split| return split.equal,
            .view => |view| return view.equal,
        }
    }

    pub fn setEqual(self: *Node, eq: bool) void {
        switch (self.*) {
            .split => |split| split.equal = eq,
            .view => |view| view.equal = eq,
        }
    }

    pub fn count(self: *const Node) usize {
        switch (self.*) {
            .view => return 1,
            .split => |s| {
                var cnt: usize = 0;
                for (s.children.items) |child| {
                    cnt += child.count();
                }
                return cnt;
            },
        }
    }

    pub fn _split(self: *Node, alloc: Allocator, id: u64, direction: Direction, after: bool) !void {
        const old_view = self.view;
        const new_split = try Split.create(alloc, direction);
        new_split.ratio = old_view.ratio;
        new_split.equal = old_view.equal;

        old_view.ratio = 1.0;
        old_view.equal = true;

        const new_view = try View.create(alloc, id);
        new_view.equal = true;

        const old_node = try alloc.create(Node);
        old_node.* = Node{ .view = old_view };

        const new_node = try alloc.create(Node);
        new_node.* = Node{ .view = new_view };

        if (after) {
            try new_split.addChild(old_node);
            try new_split.addChild(new_node);
        } else {
            try new_split.addChild(new_node);
            try new_split.addChild(old_node);
        }

        self.* = Node{ .split = new_split };
    }

    pub fn insertChild(self: *Node, idx: usize, child: *Node) !void {
        switch (self.*) {
            .view => std.debug.panic("Insert is only possible for split nodes", .{}),
            .split => |split| {
                return split.insertChild(idx, child);
            },
        }
    }

    pub fn removeChild(self: *Node, idx: usize) *Node {
        switch (self.*) {
            .view => std.debug.panic("Remove is only possible for split nodes", .{}),
            .split => |split| {
                return split.removeChild(idx);
            },
        }
    }

    pub fn get(self: *Node, index: usize) !*Node {
        switch (self.*) {
            .view => std.debug.panic("Get is only possible for split nodes", .{}),
            .split => |split| {
                return split.get(index);
            },
        }
    }

    pub fn collapse(self: *Node, alloc: Allocator) void {
        switch (self.*) {
            .view => {},
            .split => |split| {
                const parent_ratio = split.ratio;
                const child_ptr = split.removeChild(0);
                child_ptr.setRatio(parent_ratio);

                split.children.deinit(split.alloc);
                split.element.deinit();
                alloc.destroy(split);

                self.* = child_ptr.*;
                alloc.destroy(child_ptr);
            },
        }
    }
};
