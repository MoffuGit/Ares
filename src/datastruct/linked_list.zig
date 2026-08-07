//SOURCE: https://codeberg.org/ziglang/zig
//LICENSE: [ZIG]

const std = @import("std");
const debug = std.debug;
const assert = debug.assert;
const testing = std.testing;

pub fn SinglyLinkedList(T: type) type {
    return struct {
        head: ?*T = null,
        tail: ?*T = null,

        pub fn append(self: *@This(), v: *T) void {
            assert(v.next == null);

            if (self.tail) |tail| {
                tail.next = v;
                self.tail = v;
            } else {
                self.head = v;
                self.tail = v;
            }
        }

        pub fn prepend(self: *@This(), v: *T) void {
            assert(v.next == null);

            if (self.head) |head| {
                v.next = head;
                self.head = v;
            } else {
                self.head = v;
                self.tail = v;
            }
        }

        pub fn copy(self: *@This(), other: *const @This()) void {
            assert(self != other);
            const v = other.head orelse return;

            if (self.tail) |tail| {
                tail.next = v;
            } else {
                self.head = v;
            }

            self.tail = other.tail;
        }

        pub fn pop(self: *@This()) ?*T {
            const next = self.head orelse return null;

            if (self.head == self.tail) self.tail = null;

            self.head = next.next;

            next.next = null;
            return next;
        }

        pub fn empty(self: *const @This()) bool {
            return self.head == null;
        }
    };
}

pub fn reverse(T: type, indirect: *?*T) void {
    if (indirect.* == null) {
        return;
    }
    var current: *T = indirect.*.?;
    while (current.next) |next| {
        current.next = next.next;
        next.next = indirect.*;
        indirect.* = next;
    }
}

pub fn len(list: @This()) usize {
    if (list.first) |n| {
        return 1 + countChildren(n);
    } else {
        return 0;
    }
}

pub fn insertAfter(T: type, node: *T, new_node: *T) void {
    new_node.next = node.next;
    node.next = new_node;
}

pub fn removeNext(T: type, node: *T) ?*T {
    const next_node = node.next orelse return null;
    node.next = next_node.next;
    return next_node;
}

pub fn findLast(T: type, node: *T) *T {
    var it = node;
    while (true) {
        it = it.next orelse return it;
    }
}

pub fn countChildren(T: type, node: *const T) usize {
    var count: usize = 0;
    var it: ?*const T = node.next;
    while (it) |n| : (it = n.next) {
        count += 1;
    }
    return count;
}

test "basics" {
    // Types
    const Elem = struct {
        const Self = @This();
        next: ?*Self = null,
    };
    var q: SinglyLinkedList(Elem) = .{};
    try testing.expect(q.empty());

    // Elems
    var elems: [10]Elem = .{Elem{}} ** 10;

    // One
    try testing.expect(q.pop() == null);
    q.append(&elems[0]);
    try testing.expect(!q.empty());
    try testing.expect(q.pop().? == &elems[0]);
    try testing.expect(q.pop() == null);
    try testing.expect(q.empty());

    // Two
    try testing.expect(q.pop() == null);
    q.append(&elems[0]);
    q.append(&elems[1]);
    try testing.expect(q.pop().? == &elems[0]);
    try testing.expect(q.pop().? == &elems[1]);
    try testing.expect(q.pop() == null);

    // Interleaved
    try testing.expect(q.pop() == null);
    q.append(&elems[0]);
    try testing.expect(q.pop().? == &elems[0]);
    q.append(&elems[1]);
    try testing.expect(q.pop().? == &elems[1]);
    try testing.expect(q.pop() == null);
}
