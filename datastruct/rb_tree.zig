const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

pub const Color = enum {
    Black,
    Red,
};

pub fn RBTree(
    comptime T: type,
    comptime compare: *const fn (a: T, b: T) std.math.Order,
) type {
    return struct {
        const Self = @This();

        pub const Node = struct {
            value: T,
            color: Color = .Red,
            parent: ?*Node = null,
            left: ?*Node = null,
            right: ?*Node = null,
        };

        allocator: Allocator,
        root: ?*Node = null,
        len: usize = 0,

        pub fn init(allocator: Allocator) Self {
            return .{ .allocator = allocator };
        }

        /// Frees all nodes owned by the tree.
        pub fn deinit(self: *Self) void {
            self.clear();
            self.* = undefined;
        }

        /// Frees all nodes but keeps the tree usable (root = null).
        pub fn clear(self: *Self) void {
            self.free_subtree(self.root);
            self.root = null;
            self.len = 0;
        }

        fn free_subtree(self: *Self, maybe_node: ?*Node) void {
            const node = maybe_node orelse return;
            self.free_subtree(node.left);
            self.free_subtree(node.right);
            self.allocator.destroy(node);
        }

        /// Inserts `value` into the tree. If a node with an equal value already
        /// exists, returns `false` and does not insert. Otherwise returns `true`.
        pub fn insert(self: *Self, value: T) Allocator.Error!bool {
            var current = self.root;
            var parent: ?*Node = null;
            var cmp_to_parent: std.math.Order = .eq;

            while (current) |node| {
                parent = node;
                cmp_to_parent = compare(value, node.value);
                switch (cmp_to_parent) {
                    .lt => current = node.left,
                    .gt => current = node.right,
                    .eq => return false,
                }
            }

            const new_node = try self.allocator.create(Node);
            new_node.* = .{ .value = value, .parent = parent };

            if (parent == null) {
                self.root = new_node;
            } else switch (cmp_to_parent) {
                .lt => parent.?.left = new_node,
                .gt => parent.?.right = new_node,
                .eq => unreachable,
            }

            self.len += 1;
            self.insert_fixup(new_node);
            return true;
        }

        /// Returns a pointer to the value stored in the tree that compares equal
        /// to `key`, or `null` if it is not present.
        pub fn find(self: *Self, key: T) ?*T {
            var current = self.root;
            while (current) |node| {
                switch (compare(key, node.value)) {
                    .lt => current = node.left,
                    .gt => current = node.right,
                    .eq => return &node.value,
                }
            }
            return null;
        }

        fn find_node(self: *Self, key: T) ?*Node {
            var current = self.root;
            while (current) |node| {
                switch (compare(key, node.value)) {
                    .lt => current = node.left,
                    .gt => current = node.right,
                    .eq => return node,
                }
            }
            return null;
        }

        pub fn contains(self: *Self, key: T) bool {
            return self.find_node(key) != null;
        }

        pub fn findMin(self: *Self) ?*T {
            const node = self.min_node(self.root) orelse return null;
            return &node.value;
        }

        pub fn findMax(self: *Self) ?*T {
            var current = self.root orelse return null;
            while (current.right) |right_child| {
                current = right_child;
            }
            return &current.value;
        }

        fn min_node(_: *Self, maybe_node: ?*Node) ?*Node {
            var current = maybe_node orelse return null;
            while (current.left) |left_child| {
                current = left_child;
            }
            return current;
        }

        fn get_color(_: *Self, node: ?*Node) Color {
            return if (node) |n| n.color else .Black;
        }

        fn set_color(_: *Self, node: *Node, color: Color) void {
            node.color = color;
        }

        fn rotate_left(self: *Self, x: *Node) void {
            const y = x.right orelse return;
            x.right = y.left;
            if (y.left) |left_child| {
                left_child.parent = x;
            }
            y.parent = x.parent;
            if (x.parent == null) {
                self.root = y;
            } else if (x == x.parent.?.left) {
                x.parent.?.left = y;
            } else {
                x.parent.?.right = y;
            }
            y.left = x;
            x.parent = y;
        }

        fn rotate_right(self: *Self, x: *Node) void {
            const y = x.left orelse return;
            x.left = y.right;
            if (y.right) |right_child| {
                right_child.parent = x;
            }
            y.parent = x.parent;
            if (x.parent == null) {
                self.root = y;
            } else if (x == x.parent.?.right) {
                x.parent.?.right = y;
            } else {
                x.parent.?.left = y;
            }
            y.right = x;
            x.parent = y;
        }

        fn insert_fixup(self: *Self, z: *Node) void {
            var current_z = z;
            while (self.get_color(current_z.parent) == .Red) {
                const parent = current_z.parent.?;
                const grandparent = parent.parent.?;

                if (parent == grandparent.left) {
                    const uncle = grandparent.right;
                    if (self.get_color(uncle) == .Red) {
                        self.set_color(parent, .Black);
                        self.set_color(uncle.?, .Black);
                        self.set_color(grandparent, .Red);
                        current_z = grandparent;
                    } else {
                        if (current_z == parent.right) {
                            current_z = parent;
                            self.rotate_left(current_z);
                        }
                        self.set_color(current_z.parent.?, .Black);
                        self.set_color(current_z.parent.?.parent.?, .Red);
                        self.rotate_right(current_z.parent.?.parent.?);
                    }
                } else {
                    const uncle = grandparent.left;
                    if (self.get_color(uncle) == .Red) {
                        self.set_color(parent, .Black);
                        self.set_color(uncle.?, .Black);
                        self.set_color(grandparent, .Red);
                        current_z = grandparent;
                    } else {
                        if (current_z == parent.left) {
                            current_z = parent;
                            self.rotate_right(current_z);
                        }
                        self.set_color(current_z.parent.?, .Black);
                        self.set_color(current_z.parent.?.parent.?, .Red);
                        self.rotate_left(current_z.parent.?.parent.?);
                    }
                }
            }
            self.set_color(self.root.?, .Black);
        }

        fn transplant(self: *Self, u: *Node, v: ?*Node) void {
            if (u.parent == null) {
                self.root = v;
            } else if (u == u.parent.?.left) {
                u.parent.?.left = v;
            } else {
                u.parent.?.right = v;
            }
            if (v) |val_v| {
                val_v.parent = u.parent;
            }
        }

        fn delete_fixup(self: *Self, x: ?*Node, x_parent: *Node) void {
            var current_x = x;
            var current_x_parent: *Node = x_parent;

            while (current_x != self.root and self.get_color(current_x) == .Black) {
                if (current_x == current_x_parent.left) {
                    var w = current_x_parent.right.?;

                    if (self.get_color(w) == .Red) {
                        self.set_color(w, .Black);
                        self.set_color(current_x_parent, .Red);
                        self.rotate_left(current_x_parent);
                        w = current_x_parent.right.?;
                    }
                    if (self.get_color(w.left) == .Black and self.get_color(w.right) == .Black) {
                        self.set_color(w, .Red);
                        current_x = current_x_parent;
                        current_x_parent = current_x.?.parent orelse break;
                    } else {
                        if (self.get_color(w.right) == .Black) {
                            self.set_color(w.left.?, .Black);
                            self.set_color(w, .Red);
                            self.rotate_right(w);
                            w = current_x_parent.right.?;
                        }
                        self.set_color(w, self.get_color(current_x_parent));
                        self.set_color(current_x_parent, .Black);
                        self.set_color(w.right.?, .Black);
                        self.rotate_left(current_x_parent);
                        current_x = self.root;
                    }
                } else {
                    var w = current_x_parent.left.?;

                    if (self.get_color(w) == .Red) {
                        self.set_color(w, .Black);
                        self.set_color(current_x_parent, .Red);
                        self.rotate_right(current_x_parent);
                        w = current_x_parent.left.?;
                    }
                    if (self.get_color(w.right) == .Black and self.get_color(w.left) == .Black) {
                        self.set_color(w, .Red);
                        current_x = current_x_parent;
                        current_x_parent = current_x.?.parent orelse break;
                    } else {
                        if (self.get_color(w.left) == .Black) {
                            self.set_color(w.right.?, .Black);
                            self.set_color(w, .Red);
                            self.rotate_left(w);
                            w = current_x_parent.left.?;
                        }
                        self.set_color(w, self.get_color(current_x_parent));
                        self.set_color(current_x_parent, .Black);
                        self.set_color(w.left.?, .Black);
                        self.rotate_right(current_x_parent);
                        current_x = self.root;
                    }
                }
            }
            if (current_x) |val_x| {
                self.set_color(val_x, .Black);
            }
        }

        /// Removes the node whose value compares equal to `key` and returns the
        /// stored value, or `null` if the key was not found.
        pub fn remove(self: *Self, key: T) ?T {
            const z = self.find_node(key) orelse return null;
            const removed_value = z.value;

            var y = z;
            var y_original_color = self.get_color(y);
            var x: ?*Node = null;
            var x_parent_for_fixup: *Node = undefined;

            if (z.left == null) {
                x = z.right;
                x_parent_for_fixup = z.parent orelse z;
                self.transplant(z, z.right);
            } else if (z.right == null) {
                x = z.left;
                x_parent_for_fixup = z.parent orelse z;
                self.transplant(z, z.left);
            } else {
                y = self.min_node(z.right).?;
                y_original_color = self.get_color(y);
                x = y.right;
                x_parent_for_fixup = y;

                if (y.parent != z) {
                    x_parent_for_fixup = y.parent.?;
                    self.transplant(y, y.right);
                    y.right = z.right;
                    y.right.?.parent = y;
                }

                self.transplant(z, y);
                y.left = z.left;
                y.left.?.parent = y;
                self.set_color(y, self.get_color(z));
            }

            if (y_original_color == .Black) {
                if (x != self.root) {
                    self.delete_fixup(x, x_parent_for_fixup);
                } else if (self.root != null) {
                    self.set_color(self.root.?, .Black);
                }
            }

            self.allocator.destroy(z);
            self.len -= 1;
            return removed_value;
        }

        pub const Iterator = struct {
            current: ?*Node,

            pub fn next(self: *Iterator) ?*T {
                const node = self.current orelse return null;
                if (node.right) |right| {
                    var n = right;
                    while (n.left) |left| {
                        n = left;
                    }
                    self.current = n;
                } else {
                    var n = node;
                    while (n.parent) |parent| {
                        if (n == parent.left) {
                            self.current = parent;
                            return &node.value;
                        }
                        n = parent;
                    }
                    self.current = null;
                }
                return &node.value;
            }
        };

        pub fn iter(self: *Self) Iterator {
            var current = self.root;
            if (current != null) {
                while (current.?.left) |left| {
                    current = left;
                }
            }
            return .{ .current = current };
        }
    };
}

test "rb_tree insert and find" {
    const testing = std.testing;

    const compare = struct {
        fn compare(a: usize, b: usize) std.math.Order {
            return std.math.order(a, b);
        }
    }.compare;

    const Tree = RBTree(usize, compare);

    var h = Tree.init(testing.allocator);
    defer h.deinit();

    try testing.expect(try h.insert(10));
    try testing.expect(try h.insert(20));
    try testing.expect(try h.insert(5));
    try testing.expect(try h.insert(15));
    try testing.expect(try h.insert(25));

    // Inserting a duplicate must report false and not change len.
    try testing.expect(!try h.insert(10));
    try testing.expectEqual(@as(usize, 5), h.len);

    try testing.expectEqual(@as(usize, 10), h.find(10).?.*);
    try testing.expectEqual(@as(usize, 20), h.find(20).?.*);
    try testing.expectEqual(@as(usize, 5), h.find(5).?.*);
    try testing.expectEqual(@as(usize, 15), h.find(15).?.*);
    try testing.expectEqual(@as(usize, 25), h.find(25).?.*);
    try testing.expect(h.find(99) == null);

    try testing.expectEqual(@as(usize, 5), h.findMin().?.*);
    try testing.expectEqual(@as(usize, 25), h.findMax().?.*);

    try testing.expect(h.root.?.color == .Black);
}

test "rb_tree remove" {
    const testing = std.testing;

    const compare = struct {
        fn compare(a: usize, b: usize) std.math.Order {
            return std.math.order(a, b);
        }
    }.compare;

    const Tree = RBTree(usize, compare);

    var h = Tree.init(testing.allocator);
    defer h.deinit();

    const values = [_]usize{ 10, 20, 5, 15, 25, 30, 2, 7, 12, 17 };
    for (values) |v| {
        try testing.expect(try h.insert(v));
    }

    try testing.expectEqual(@as(usize, 10), h.find(10).?.*);
    try testing.expectEqual(@as(usize, 2), h.find(2).?.*);
    try testing.expectEqual(@as(usize, 2), h.findMin().?.*);
    try testing.expectEqual(@as(usize, 30), h.findMax().?.*);

    // Remove non-existent
    try testing.expect(h.remove(99) == null);
    try testing.expectEqual(@as(usize, 2), h.findMin().?.*);

    // Leaf
    try testing.expectEqual(@as(usize, 2), h.remove(2).?);
    try testing.expect(h.find(2) == null);
    try testing.expectEqual(@as(usize, 5), h.findMin().?.*);

    try testing.expectEqual(@as(usize, 7), h.remove(7).?);
    try testing.expect(h.find(7) == null);

    try testing.expectEqual(@as(usize, 10), h.remove(10).?);
    try testing.expect(h.find(10) == null);
    try testing.expectEqual(@as(usize, 12), h.find(12).?.*);

    _ = h.remove(5);
    _ = h.remove(12);
    _ = h.remove(15);
    _ = h.remove(17);
    _ = h.remove(20);
    _ = h.remove(25);
    _ = h.remove(30);

    try testing.expect(h.root == null);
    try testing.expectEqual(@as(usize, 0), h.len);
    try testing.expect(h.findMin() == null);
    try testing.expect(h.findMax() == null);

    try testing.expect(try h.insert(100));
    try testing.expect(try h.insert(50));
    try testing.expectEqual(Color.Black, h.root.?.color);
    try testing.expectEqual(@as(usize, 50), h.findMin().?.*);
    try testing.expectEqual(@as(usize, 100), h.findMax().?.*);

    _ = h.remove(100);
    _ = h.remove(50);
    try testing.expect(h.root == null);
}

test "rb_tree iterator yields sorted order" {
    const testing = std.testing;

    const compare = struct {
        fn compare(a: i32, b: i32) std.math.Order {
            return std.math.order(a, b);
        }
    }.compare;

    const Tree = RBTree(i32, compare);

    var h = Tree.init(testing.allocator);
    defer h.deinit();

    const values = [_]i32{ 4, 1, 7, 3, 9, 2, 8, 5, 6 };
    for (values) |v| {
        _ = try h.insert(v);
    }

    var it = h.iter();
    var expected: i32 = 1;
    while (it.next()) |v| {
        try testing.expectEqual(expected, v.*);
        expected += 1;
    }
    try testing.expectEqual(@as(i32, 10), expected);
}

test "rb_tree clear empties the tree" {
    const testing = std.testing;

    const compare = struct {
        fn compare(a: u32, b: u32) std.math.Order {
            return std.math.order(a, b);
        }
    }.compare;

    const Tree = RBTree(u32, compare);

    var h = Tree.init(testing.allocator);
    defer h.deinit();

    for ([_]u32{ 3, 1, 4, 1, 5, 9, 2, 6 }) |v| {
        _ = try h.insert(v);
    }

    h.clear();
    try testing.expect(h.root == null);
    try testing.expectEqual(@as(usize, 0), h.len);

    _ = try h.insert(42);
    try testing.expectEqual(@as(u32, 42), h.findMin().?.*);
}
