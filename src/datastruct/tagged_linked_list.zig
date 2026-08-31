const std = @import("std");
const testing = std.testing;

const SinglyLinkedList = @import("linked_list.zig").SinglyLinkedList;

pub fn TaggedLinkedList(Union: type) type {
    return struct {
        const info = @typeInfo(Union).@"union";

        const UnionTag = info.tag_type orelse
            @compileError("TaggedLinkedListCollection requires a tagged union");

        const fields = info.fields;

        pub const Values = Union;

        pub const Tag = UnionTag;

        pub fn Value(comptime tag: Tag) type {
            return @FieldType(Union, @tagName(tag));
        }

        pub fn Node(comptime tag: Tag) type {
            return struct {
                next: ?*@This() = null,
                value: Value(tag),
            };
        }

        pub const Lists = bkl: {
            var field_names: [fields.len][]const u8 = undefined;
            var field_types: [fields.len]type = undefined;
            var field_attrs: [fields.len]std.builtin.Type.StructField.Attributes = undefined;

            for (fields, &field_names, &field_types, &field_attrs) |field, *name, *Type, *attr| {
                const tag: Tag = @field(Tag, field.name);
                name.* = field.name;
                Type.* = SinglyLinkedList(Node(tag));
                attr.* = .{ .@"align" = @alignOf(Type.*) };
            }

            break :bkl @Struct(.auto, null, &field_names, &field_types, &field_attrs);
        };

        pub const empty: @This() = bkl: {
            var lists: Lists = undefined;
            for (fields) |field| {
                @field(lists, field.name) = .empty;
            }
            break :bkl .{ .lists = lists };
        };

        lists: Lists,

        pub fn List(comptime tag: Tag) type {
            return @FieldType(Lists, @tagName(tag));
        }

        pub fn get(self: *@This(), comptime tag: Tag) *SinglyLinkedList(Node(tag)) {
            return &@field(self.lists, @tagName(tag));
        }

        pub fn append(self: *@This(), comptime tag: Tag, node: *Node(tag)) void {
            self.get(tag).append(node);
        }

        pub fn prepend(self: *@This(), comptime tag: Tag, node: *Node(tag)) void {
            self.get(tag).prepend(node);
        }

        pub fn pop(self: *@This(), comptime tag: Tag) ?*Node(tag) {
            return self.get(tag).pop();
        }
    };
}

test "generates linked nodes from a tagged value union" {
    const Value = union(enum) {
        number: u8,
        text: []const u8,
    };
    const Collection = TaggedLinkedList(Value);

    var collection: Collection = .empty;
    var number: Collection.Node(.number) = .{ .value = 42 };
    var text: Collection.Node(.text) = .{ .value = "hello" };

    collection.prepend(.number, &number);
    collection.prepend(.text, &text);

    const number_list = collection.get(.number);
    try testing.expect(number_list.head == &number);
    try testing.expectEqual(@as(u8, 42), collection.pop(.number).?.value);
    try testing.expectEqualStrings("hello", collection.pop(.text).?.value);
}
