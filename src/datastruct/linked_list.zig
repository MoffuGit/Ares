//Source: https://github.com/mitchellh/libxev
//License; [LIBXEV]

const std = @import("std");
const debug = std.debug;
const assert = debug.assert;
const testing = std.testing;

pub fn SinglyLinkedList(T: type) type {
    return struct {
        pub const empty: @This() = .{
            .head = null,
            .tail = null,
        };

        head: ?*T,
        tail: ?*T,

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

        pub fn is_empty(self: *const @This()) bool {
            return self.head == null;
        }
    };
}

test "basics" {
    // Types
    const Elem = struct {
        const Self = @This();
        next: ?*Self = null,
    };
    var q: SinglyLinkedList(Elem) = .{};
    try testing.expect(q.is_empty());

    // Elems
    var elems: [10]Elem = .{Elem{}} ** 10;

    // One
    try testing.expect(q.pop() == null);
    q.append(&elems[0]);
    try testing.expect(!q.is_empty());
    try testing.expectEqual(q.pop().?, &elems[0]);
    try testing.expectEqual(q.pop(), null);
    try testing.expect(q.is_empty());

    // Two
    try testing.expectEqual(q.pop(), null);
    q.append(&elems[0]);
    q.append(&elems[1]);
    try testing.expectEqual(q.pop().?, &elems[0]);
    try testing.expectEqual(q.pop().?, &elems[1]);
    try testing.expectEqual(q.pop(), null);

    // Interleaved
    try testing.expectEqual(q.pop(), null);
    q.append(&elems[0]);
    try testing.expectEqual(q.pop().?, &elems[0]);
    q.append(&elems[1]);
    try testing.expectEqual(q.pop().?, &elems[1]);
    try testing.expectEqual(q.pop(), null);

    // One
    try testing.expectEqual(q.pop(), null);
    q.prepend(&elems[0]);
    try testing.expect(!q.is_empty());
    try testing.expectEqual(q.pop().?, &elems[0]);
    try testing.expectEqual(q.pop(), null);
    try testing.expect(q.is_empty());

    // Two
    try testing.expect(q.pop() == null);
    q.prepend(&elems[0]);
    q.prepend(&elems[1]);
    try testing.expectEqual(q.pop().?, &elems[1]);
    try testing.expectEqual(q.pop().?, &elems[0]);
    try testing.expect(q.pop() == null);

    // Interleaved
    try testing.expect(q.pop() == null);
    q.prepend(&elems[0]);
    try testing.expect(q.pop().? == &elems[0]);
    q.prepend(&elems[1]);
    try testing.expect(q.pop().? == &elems[1]);
    try testing.expect(q.pop() == null);

    q.prepend(&elems[0]);
    q.append(&elems[1]);
    q.prepend(&elems[2]);
    q.append(&elems[4]);

    try testing.expect(q.pop().? == &elems[2]);
    try testing.expect(q.pop().? == &elems[0]);
    try testing.expect(q.pop().? == &elems[1]);
    try testing.expect(q.pop().? == &elems[4]);
}
