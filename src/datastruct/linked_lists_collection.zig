const std = @import("std");
const testing = std.testing;

const SinglyLinkedList = @import("linked_list.zig").SinglyLinkedList;

pub fn LinkedListCollection(Union: type) type {
    return struct {
        const union_info = @typeInfo(Union).@"union";
        const Tag = union_info.tag_type orelse
            @compileError("TaggedLinkedLists requires a tagged union");

        const fields = union_info.fields;

        const Lists = bkl: {
            var field_names: [fields.len][]const u8 = undefined;
            var field_types: [fields.len]type = undefined;
            var fiels_attrs: [fields.len]std.builtin.Type.StructField.Attributes = undefined;

            for (fields, &field_names, &field_types, &fiels_attrs) |field, *name, *Type, *attr| {
                name.* = field.name;
                Type.* = SinglyLinkedList(field.type);
                attr.* = .{ .@"align" = field.alignment };
            }
            break :bkl @Struct(.auto, null, &field_names, &field_types, &fiels_attrs);
        };

        pub const empty: @This() = bkl: {
            var lists: Lists = undefined;
            for (fields) |field| {
                @field(lists, field.name) = .empty;
            }
            break :bkl .{ .lists = lists };
        };

        lists: Lists,

        fn Payload(comptime tag: Tag) type {
            return @FieldType(Union, @tagName(tag));
        }

        fn List(comptime tag: Tag) type {
            return @FieldType(Lists, @tagName(tag));
        }

        pub fn get(self: *@This(), comptime tag: Tag) *List(tag) {
            return &@field(self.lists, @tagName(tag));
        }

        pub fn append(self: *@This(), comptime tag: Tag, value: *Payload(tag)) void {
            @field(self.lists, @tagName(tag)).append(value);
        }

        pub fn prepend(self: *@This(), comptime tag: Tag, value: *Payload(tag)) void {
            @field(self.lists, @tagName(tag)).prepend(value);
        }

        pub fn pop(self: *@This(), comptime tag: Tag) ?*Payload(tag) {
            return @field(self.lists, @tagName(tag)).pop();
        }
    };
}

test "stores one linked list per union tag" {
    const NodeA = struct {
        value: u8,
        next: ?*@This() = null,
    };
    const NodeB = struct {
        value: []const u8,
        next: ?*@This() = null,
    };
    const Item = union(enum) {
        a: NodeA,
        b: NodeB,
    };

    var lists: LinkedListCollection(Item) = .empty;
    var a1: NodeA = .{ .value = 1 };
    var a2: NodeA = .{ .value = 2 };
    var b: NodeB = .{ .value = "three" };

    lists.append(.a, &a1);
    lists.append(.b, &b);
    lists.append(.a, &a2);

    const a_list: *SinglyLinkedList(NodeA) = lists.get(.a);
    try testing.expect(a_list.head == &a1);

    const popped_a1 = lists.pop(.a);
    const popped_b = lists.pop(.b);
    const popped_a2 = lists.pop(.a);

    try testing.expectEqual(@as(u8, 1), popped_a1.?.value);
    try testing.expectEqualStrings("three", popped_b.?.value);
    try testing.expectEqual(@as(u8, 2), popped_a2.?.value);
    try testing.expect(lists.pop(.a) == null);
    try testing.expect(lists.pop(.b) == null);
}
