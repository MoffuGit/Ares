const std = @import("std");
const Allocator = std.mem.Allocator;

const NodePath = @import("mod.zig").NodePath;

pub const Direction = enum {
    horizontal,
    vertical,
};

pub const Split = struct {
    direction: Direction,
    children: std.ArrayList(*Node) = .{},
    alloc: Allocator,
    ratio: ?f32 = null,

    pub fn init(alloc: Allocator, direction: Direction) Split {
        return .{
            .direction = direction,
            .alloc = alloc,
        };
    }

    pub fn deinit(self: *Split) void {
        for (self.children.items) |child| {
            child.deinit();
            self.alloc.destroy(child);
        }
        self.children.deinit(self.alloc);
    }

    pub fn addChild(self: *Split, node: Node) !void {
        const node_ptr = try self.alloc.create(Node);
        node_ptr.* = node;
        try self.children.append(self.alloc, node_ptr);
    }

    pub fn insertChild(self: *Split, index: usize, node: Node) !void {
        const node_ptr = try self.alloc.create(Node);
        node_ptr.* = node;
        try self.children.insert(self.alloc, index, node_ptr);
    }

    pub fn get(self: *Split, index: usize) !*Node {
        if (index >= self.children.items.len) return error.OutOfBounds;
        return self.children.items[index];
    }

    pub fn removeChild(self: *Split, index: usize) *Node {
        return self.children.orderedRemove(index);
    }

    pub fn childCount(self: *const Split) usize {
        return self.children.items.len;
    }
};

pub const View = struct {
    id: u64,
    ratio: ?f32 = null,

    pub fn init(id: u64) View {
        return .{ .id = id };
    }
};

pub const Node = union(enum) {
    split: Split,
    view: View,

    pub fn deinit(self: *Node) void {
        switch (self.*) {
            .split => |*s| s.deinit(),
            .view => {},
        }
    }

    pub fn find(node: *Node, id: u64) ?*Node {
        switch (node.*) {
            .view => |v| {
                if (v.id == id) return node;
            },
            .split => |*s| {
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
            .split => |*s| {
                for (s.children.items, 0..) |child, i| {
                    _path.append(alloc, i) catch return false;
                    if (child.findPath(alloc, id, _path)) return true;
                    _ = _path.pop();
                }
            },
        }
        return false;
    }

    pub fn ratio(self: *Node) ?f32 {
        switch (self.*) {
            .split => |split| {
                return split.ratio;
            },
            .view => |view| {
                return view.ratio;
            },
        }
    }

    pub fn setRatio(self: *Node, r: ?f32) void {
        switch (self.*) {
            .split => |*split| {
                split.ratio = r;
            },
            .view => |*view| {
                view.ratio = r;
            },
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
        var new_split = Split.init(alloc, direction);
        new_split.ratio = self.ratio();

        var old_view = self.*;
        old_view.setRatio(null);

        const new_view = Node{ .view = View.init(id) };

        if (after) {
            try new_split.addChild(old_view);
            try new_split.addChild(new_view);
        } else {
            try new_split.addChild(new_view);
            try new_split.addChild(old_view);
        }

        self.* = Node{ .split = new_split };
    }

    pub fn insertChild(self: *Node, idx: usize, child: Node) !void {
        switch (self.*) {
            .view => std.debug.panic("Insert is only possible for split nodes", .{}),
            .split => |*split| {
                return split.insertChild(idx, child);
            },
        }
    }

    pub fn removeChild(self: *Node, idx: usize) *Node {
        switch (self.*) {
            .view => std.debug.panic("Remove is only possible for split nodes", .{}),
            .split => |*split| {
                return split.removeChild(idx);
            },
        }
    }

    pub fn get(self: *Node, index: usize) !*Node {
        switch (self.*) {
            .view => std.debug.panic("Get is only possible for split nodes", .{}),
            .split => |*split| {
                return split.get(index);
            },
        }
    }

    pub fn collapse(self: *Node) void {
        switch (self.*) {
            .view => {},
            .split => |*split| {
                const parent_ratio = split.ratio;
                const child_ptr = split.removeChild(0);
                var child = child_ptr.*;
                child.setRatio(parent_ratio);
                split.alloc.destroy(child_ptr);
                split.children.deinit(split.alloc);
                self.* = child;
            },
        }
    }
};
