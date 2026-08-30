const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;
const fmt = std.fmt;

pub fn SinglyLinkedList(T: type, comptime next_field: []const u8) type {
    return struct {
        pub const empty: @This() = .{
            .head = null,
            .tail = null,
        };

        head: ?*T,
        tail: ?*T,

        pub fn append(self: *@This(), value: *T) void {
            assert(@field(value, next_field) == null);

            if (self.tail) |tail| {
                @field(tail, next_field) = value;
                self.tail = value;
            } else {
                self.head = value;
                self.tail = value;
            }
        }

        pub fn prepend(self: *@This(), value: *T) void {
            assert(@field(value, next_field) == null);

            if (self.head) |head| {
                @field(value, next_field) = head;
                self.head = value;
            } else {
                self.head = value;
                self.tail = value;
            }
        }

        pub fn concatByMoving(self: *@This(), other: *@This()) void {
            const head = other.head orelse return;

            if (self.tail) |tail| {
                @field(tail, next_field) = head;
            } else {
                self.head = head;
            }

            self.tail = other.tail;
            other.head = null;
            other.tail = null;
        }

        pub fn pop(self: *@This()) ?*T {
            const head = self.head orelse return null;

            if (self.head == self.tail) self.tail = null;
            self.head = @field(head, next_field);
            @field(head, next_field) = null;
            return head;
        }

        pub fn is_empty(self: *const @This()) bool {
            return self.head == null;
        }
    };
}

test "uses the selected link field" {
    const Elem = struct {
        value: u8,
        next_a: ?*@This() = null,
        next_b: ?*@This() = null,
    };
    const ListA = SinglyLinkedList(Elem, "next_a");
    const ListB = SinglyLinkedList(Elem, "next_b");

    var one: Elem = .{ .value = 1 };
    var two: Elem = .{ .value = 2 };
    var list_a: ListA = .empty;
    var list_b: ListB = .empty;

    list_a.append(&one);
    list_a.append(&two);
    list_b.append(&two);
    list_b.append(&one);

    try testing.expectEqual(@as(u8, 1), list_a.pop().?.value);
    try testing.expectEqual(@as(u8, 2), list_a.pop().?.value);
    try testing.expectEqual(@as(u8, 2), list_b.pop().?.value);
    try testing.expectEqual(@as(u8, 1), list_b.pop().?.value);
    try testing.expect(list_a.is_empty());
    try testing.expect(list_b.is_empty());
}

test "concatenates using the selected link field" {
    const Elem = struct {
        value: u8,
        next_struct: ?*@This() = null,
    };
    const List = SinglyLinkedList(Elem, "next_struct");

    var one: Elem = .{ .value = 1 };
    var two: Elem = .{ .value = 2 };
    var first: List = .empty;
    var second: List = .empty;

    first.prepend(&one);
    second.prepend(&two);
    first.concatByMoving(&second);

    try testing.expect(second.is_empty());
    try testing.expectEqual(@as(u8, 1), first.pop().?.value);
    try testing.expectEqual(@as(u8, 2), first.pop().?.value);
}
