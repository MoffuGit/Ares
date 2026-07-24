//SOURCE: https://codeberg.org/ziglang/zig
//LICENSE: [ZIG]

const std = @import("std");
const debug = std.debug;
const assert = debug.assert;
const testing = std.testing;

pub fn SinglyLinkedList(T: type) type {
    return struct {
        const Node = T;

        first: ?*Node = null,

        pub fn insertAfter(node: *Node, new_node: *Node) void {
            new_node.next = node.next;
            node.next = new_node;
        }

        pub fn removeNext(node: *Node) ?*Node {
            const next_node = node.next orelse return null;
            node.next = next_node.next;
            return next_node;
        }

        pub fn findLast(node: *Node) *Node {
            var it = node;
            while (true) {
                it = it.next orelse return it;
            }
        }

        pub fn countChildren(node: *const Node) usize {
            var count: usize = 0;
            var it: ?*const Node = node.next;
            while (it) |n| : (it = n.next) {
                count += 1;
            }
            return count;
        }

        pub fn reverse(indirect: *?*Node) void {
            if (indirect.* == null) {
                return;
            }
            var current: *Node = indirect.*.?;
            while (current.next) |next| {
                current.next = next.next;
                next.next = indirect.*;
                indirect.* = next;
            }
        }

        pub fn prepend(list: *@This(), new_node: *Node) void {
            new_node.next = list.first;
            list.first = new_node;
        }

        pub fn remove(list: *@This(), node: *Node) void {
            if (list.first == node) {
                list.first = node.next;
            } else {
                var current_elm = list.first.?;
                while (current_elm.next != node) {
                    current_elm = current_elm.next.?;
                }
                current_elm.next = node.next;
            }
        }

        pub fn popFirst(list: *@This()) ?*Node {
            const first = list.first orelse return null;
            list.first = first.next;
            return first;
        }

        pub fn len(list: @This()) usize {
            if (list.first) |n| {
                return 1 + countChildren(n);
            } else {
                return 0;
            }
        }
    };
}

test "basics" {
    const L = struct {
        data: u32,
        next: ?*@This() = null,
    };
    var list: SinglyLinkedList(L) = .{};

    try testing.expect(list.len() == 0);

    var one: L = .{ .data = 1 };
    var two: L = .{ .data = 2 };
    var three: L = .{ .data = 3 };
    var four: L = .{ .data = 4 };
    var five: L = .{ .data = 5 };

    list.prepend(&two); // {2}
    SinglyLinkedList(L).insertAfter(&two, &five);
    list.prepend(&one); // {1, 2, 5}
    SinglyLinkedList(L).insertAfter(&two, &three);
    SinglyLinkedList(L).insertAfter(&three, &four);

    try testing.expect(list.len() == 5);

    // Traverse forwards.
    {
        var it = list.first;
        var index: u32 = 1;
        while (it) |node| : (it = node.next) {
            try testing.expect(node.data == index);
            index += 1;
        }
    }

    _ = list.popFirst(); // {2, 3, 4, 5}
    _ = list.remove(&five); // {2, 3, 4}
    _ = SinglyLinkedList(L).removeNext(&two);

    try testing.expect(list.first.?.data == 2);
    try testing.expect(list.first.?.next.?.data == 4);
    try testing.expect(list.first.?.next.?.next == null);

    SinglyLinkedList(L).reverse(&list.first);

    try testing.expect(list.first.?.data == 4);
    try testing.expect(list.first.?.next.?.data == 2);
    try testing.expect(list.first.?.next.?.next == null);
}
