const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const BASE: usize = 6;

//i have a notion of what i need to do
//but i need to keep reading over the zed sumtree
//and teh zig b plus tree repo
//with that two things i can write my own b plus tree

pub fn NodeType(comptime K: type, comptime V: type) type {
    return union(enum) {
        const Self = @This();

        Internal: struct { edge: [2 * BASE]*Self = undefined, keys: [2 * BASE - 1]K = undefined, len: u16 = 0 },
        Leaf: struct { items: [2 * BASE - 1]V = undefined, keys: [2 * BASE - 1]K = undefined, len: u16 = 0, next: ?*Self = null },
        //is_empty
        //is_leaf
        //items
        //panic when a call is for a wrogn type of Node
        //etc...
    };
}

pub fn BPlusTree(comptime K: type, comptime V: type, comptime comp: *const fn (a: *K, b: *K) std.math.Order) type {
    _ = comp;
    const Node = NodeType(K, V);

    return struct {
        const Self = @This();

        root: *Node,
        alloc: Allocator,

        pub fn init(alloc: Allocator) !Self {
            const root = try alloc.create(Node);
            root.* = .{ .Leaf = .{} };

            return .{ .root = root, .alloc = alloc };
        }

        pub fn deinit(self: Self) void {
            self.alloc.destroy(self.root);
        }

        pub fn push(self: *Self, key: K, value: V) !void {
            const node = try self.alloc.create(Node);
            node.* = .{ .Leaf = .{} };
            //now i needc to add the key and the value inside the buffers
            //update the length
            //and call append
        }

        //     pub fn push(&mut self, item: T, cx: <T::Summary as Summary>::Context<'_>) {
        //     let summary = item.summary(cx);
        //     self.append(
        //         SumTree(Arc::new(Node::Leaf {
        //             summary: summary.clone(),
        //             items: ArrayVec::from_iter(Some(item)),
        //             item_summaries: ArrayVec::from_iter(Some(summary)),
        //         })),
        //         cx,
        //     );
        // }

        //append:
        //  (self, nodeA, nodeB)
        //  if nodeA is empty
        //  root = nodeB
        //  alloc.destroy(nodeA)
        //
        //  else
        //  if height of nodeA is less thatn the height from nodeB
        //  remove childrens from nodeB until the height is the same
        //
        //  else
        //  the height is equal or less than NodeA
        //  try to push_recursive, this will split the nodes and and borrow and merge
        //  this will set on NodeA one side of the tree, on the nodeB another side of the tree
        //  latter they will get join and after that you can set NodeA as the result Node of the
        //  join, you need to remember when to destroy
        //
        //  try to remove subnodes from nodeB until the height is equal to the current height of the tree
        //  and try to append this ones
        //
        //     if self.is_empty() {
        //         *self = other;
        //     } else if !other.0.is_leaf() || !other.0.items().is_empty() {
        //         if self.0.height() < other.0.height() {
        //             for tree in other.0.child_trees() {
        //                 self.append(tree.clone(), cx);
        //             }
        //         } else if let Some(split_tree) = self.push_tree_recursive(other, cx) {
        //             *self = Self::from_child_trees(self.clone(), split_tree, cx);
        //         }
        //     }
        // }

        //remember you are going to shift and unshift the values inside the buffers of the node
        //this is done for adding and removing when there is no need of splitting
        //push(self, k, t)
        // create a Node
        // and call
        //append(self, node one, node two)
        //...
        //split
        //merge
        //borrow
        //...
        //join(self, other tree)
        //...
        //delete
        //etc...:w
        //
        //replace root node for other node, when calling something like from_child_trees, root = new_tree
    };
}

fn test_comp(a: *usize, b: *usize) std.math.Order {
    return std.math.order(a.*, b.*);
}

test "init B+ tree" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const T = BPlusTree(usize, usize, test_comp);
    const tree = try T.init(alloc);
    defer tree.deinit();
}
