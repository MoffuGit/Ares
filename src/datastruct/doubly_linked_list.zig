const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;
const fmt = std.fmt;

pub fn DoublyLinkedList(T: type, comptime next_field: []const u8, comptime prev_field: []const u8) type {
    return struct {
        pub const empty: @This() = .{ .first = null, .last = null };

        first: ?*T,
        last: ?*T,

        pub fn insertAfter(self: *@This(), existing_node: *T, new_node: *T) void {
            assert(@field(new_node, next_field) == null);
            assert(@field(new_node, prev_field) == null);

            @field(new_node, prev_field) = existing_node;
            if (@field(existing_node, next_field)) |next_node| {
                @field(new_node, next_field) = next_node;
                @field(next_node, prev_field) = new_node;
            } else {
                self.last = new_node;
            }
            @field(existing_node, next_field) = new_node;
        }

        pub fn insertBefore(self: *@This(), existing_node: *T, new_node: *T) void {
            assert(@field(new_node, next_field) == null);
            assert(@field(new_node, prev_field) == null);

            @field(new_node, next_field) = existing_node;
            if (@field(existing_node, prev_field)) |prev_node| {
                @field(new_node, prev_field) = prev_node;
                @field(prev_node, next_field) = new_node;
            } else {
                self.first = new_node;
            }
            @field(existing_node, prev_field) = new_node;
        }

        pub fn concatByMoving(self: *@This(), other: *@This()) void {
            const first = other.first orelse return;

            if (self.last) |last| {
                @field(last, next_field) = first;
                @field(first, prev_field) = last;
            } else {
                self.first = first;
            }

            self.last = other.last;
            other.first = null;
            other.last = null;
        }

        pub fn append(self: *@This(), value: *T) void {
            assert(@field(value, next_field) == null);
            assert(@field(value, prev_field) == null);

            if (self.last) |last| {
                self.insertAfter(last, value);
            } else {
                self.first = value;
                self.last = value;
            }
        }

        pub fn prepend(self: *@This(), value: *T) void {
            assert(@field(value, next_field) == null);
            assert(@field(value, prev_field) == null);

            if (self.first) |first| {
                self.insertBefore(first, value);
            } else {
                self.first = value;
                self.last = value;
            }
        }

        pub fn remove(self: *@This(), value: *T) void {
            const prev = @field(value, prev_field);
            const next = @field(value, next_field);

            if (prev) |prev_node| {
                @field(prev_node, next_field) = next;
            } else {
                self.first = next;
            }

            if (next) |next_node| {
                @field(next_node, prev_field) = prev;
            } else {
                self.last = prev;
            }

            @field(value, next_field) = null;
            @field(value, prev_field) = null;
        }

        pub fn pop(self: *@This()) ?*T {
            const last = self.last orelse return null;
            self.remove(last);
            return last;
        }

        pub fn popFirst(self: *@This()) ?*T {
            const first = self.first orelse return null;
            self.remove(first);
            return first;
        }

        pub fn len(self: *const @This()) usize {
            var count: usize = 0;
            var it = self.first;
            while (it) |node| : (it = @field(node, next_field)) count += 1;
            return count;
        }

        pub fn is_empty(self: *const @This()) bool {
            return self.first == null;
        }
    };
}

test "uses the selected link fields" {
    const L = struct {
        data: u32,
        list_next: ?*@This() = null,
        list_prev: ?*@This() = null,
    };
    var list: DoublyLinkedList(L, "list_next", "list_prev") = .empty;

    var one: L = .{ .data = 1 };
    var two: L = .{ .data = 2 };
    var three: L = .{ .data = 3 };
    var four: L = .{ .data = 4 };
    var five: L = .{ .data = 5 };

    list.append(&two); // {2}
    list.append(&five); // {2, 5}
    list.prepend(&one); // {1, 2, 5}
    list.insertBefore(&five, &four); // {1, 2, 4, 5}
    list.insertAfter(&two, &three); // {1, 2, 3, 4, 5}

    // Traverse forwards.
    {
        var it = list.first;
        var index: u32 = 1;
        while (it) |node| : (it = node.list_next) {
            try testing.expect(node.data == index);
            index += 1;
        }
    }

    // Traverse backwards.
    {
        var it = list.last;
        var index: u32 = 1;
        while (it) |node| : (it = node.list_prev) {
            try testing.expect(node.data == (6 - index));
            index += 1;
        }
    }

    _ = list.popFirst(); // {2, 3, 4, 5}
    _ = list.pop(); // {2, 3, 4}
    list.remove(&three); // {2, 4}

    try testing.expect(list.first.?.data == 2);
    try testing.expect(list.last.?.data == 4);
    try testing.expect(list.len() == 2);
    try testing.expect(one.list_next == null and one.list_prev == null);
    try testing.expect(three.list_next == null and three.list_prev == null);
    try testing.expect(five.list_next == null and five.list_prev == null);
}

test "concatenation" {
    const L = struct {
        data: u32,
        next: ?*@This() = null,
        prev: ?*@This() = null,
    };
    var list1: DoublyLinkedList(L, "next", "prev") = .empty;
    var list2: DoublyLinkedList(L, "next", "prev") = .empty;

    var one: L = .{ .data = 1 };
    var two: L = .{ .data = 2 };
    var three: L = .{ .data = 3 };
    var four: L = .{ .data = 4 };
    var five: L = .{ .data = 5 };

    list1.append(&one);
    list1.append(&two);
    list2.append(&three);
    list2.append(&four);
    list2.append(&five);

    list1.concatByMoving(&list2);

    try testing.expect(list1.last == &five);
    try testing.expect(list1.len() == 5);
    try testing.expect(list2.first == null);
    try testing.expect(list2.last == null);
    try testing.expect(list2.len() == 0);

    // Traverse forwards.
    {
        var it = list1.first;
        var index: u32 = 1;
        while (it) |node| : (it = node.next) {
            try testing.expect(node.data == index);
            index += 1;
        }
    }

    // Traverse backwards.
    {
        var it = list1.last;
        var index: u32 = 1;
        while (it) |node| : (it = node.prev) {
            try testing.expect(node.data == (6 - index));
            index += 1;
        }
    }

    // Swap them back, this verifies that concatenating to an empty list works.
    list2.concatByMoving(&list1);

    // Traverse forwards.
    {
        var it = list2.first;
        var index: u32 = 1;
        while (it) |node| : (it = node.next) {
            try testing.expect(node.data == index);
            index += 1;
        }
    }

    // Traverse backwards.
    {
        var it = list2.last;
        var index: u32 = 1;
        while (it) |node| : (it = node.prev) {
            try testing.expect(node.data == (6 - index));
            index += 1;
        }
    }
}
