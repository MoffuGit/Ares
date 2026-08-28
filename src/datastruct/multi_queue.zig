const std = @import("std");

const linked_list = @import("linked_list.zig");

/// Multiple intrusive queues addressed by the tags of `Queues`.
///
/// `Queues` must be a tagged union whose fields are queue names and whose field
/// types are intrusive element types. Each element type must provide `next` with
/// type `?*T`, matching `intrusive_queue.Intrusive(T)`.
pub fn MultiQueue(comptime Queues: type) type {
    const info = @typeInfo(Queues);
    if (info != .@"union") @compileError("MultiIntrusive expects a union type");

    const union_info = info.@"union";
    const Tag = union_info.tag_type orelse @compileError("MultiIntrusive expects a tagged union");
    const fields = union_info.fields;

    const Queue = blk: {
        var field_names: [fields.len][]const u8 = undefined;
        var field_types: [fields.len]type = undefined;
        var field_attrs: [fields.len]std.builtin.Type.UnionField.Attributes = undefined;
        for (fields, &field_names, &field_types, &field_attrs) |field, *name, *Type, *attrs| {
            const QueueType = linked_list.SinglyLinkedList(field.type);
            name.* = field.name;
            Type.* = QueueType;
            attrs.* = .{ .@"align" = @alignOf(QueueType) };
        }
        break :blk @Union(.auto, null, &field_names, &field_types, &field_attrs);
    };

    return struct {
        const Self = @This();

        queues: [fields.len]Queue,

        pub fn init(self: *Self) void {
            @setRuntimeSafety(false);
            inline for (fields, 0..) |field, i| {
                @field(self.queues[i], field.name) = .empty;
            }
        }

        pub fn push(self: *Self, comptime tag: Tag, value: *FieldType(tag)) void {
            queue(self, tag).append(value);
        }

        pub fn pop(self: *Self, comptime tag: Tag) ?*FieldType(tag) {
            return queue(self, tag).pop();
        }

        pub fn empty(self: *Self, comptime tag: Tag) bool {
            return queue(self, tag).is_empty();
        }

        pub fn queue(self: *Self, comptime tag: Tag) *linked_list.SinglyLinkedList(FieldType(tag)) {
            @setRuntimeSafety(false);
            return &@field(self.queues[@intFromEnum(tag)], @tagName(tag));
        }

        pub fn FieldType(comptime tag: Tag) type {
            return @FieldType(Queues, @tagName(tag));
        }
    };
}

test "Multi Queue Test" {
    const Completion = struct {
        const Self = @This();
        id: usize = 0,
        next: ?*Self = null,
    };

    const Queues = union(enum) {
        cancellations: Completion,
        completions: Completion,
        submissions: Completion,
    };

    var queues: MultiQueue(Queues) = undefined;
    queues.init();

    try std.testing.expect(queues.empty(.cancellations));
    try std.testing.expect(queues.empty(.completions));
    try std.testing.expect(queues.empty(.submissions));

    var cancellations: [2]Completion = .{
        .{ .id = 1 },
        .{ .id = 2 },
    };
    var completions: [2]Completion = .{
        .{ .id = 3 },
        .{ .id = 4 },
    };
    var submissions: [2]Completion = .{
        .{ .id = 5 },
        .{ .id = 6 },
    };

    queues.push(.cancellations, &cancellations[0]);
    queues.push(.completions, &completions[0]);
    queues.push(.submissions, &submissions[0]);
    queues.push(.cancellations, &cancellations[1]);
    queues.push(.completions, &completions[1]);
    queues.push(.submissions, &submissions[1]);

    try std.testing.expectEqual(@as(usize, 1), queues.pop(.cancellations).?.id);
    try std.testing.expectEqual(@as(usize, 2), queues.pop(.cancellations).?.id);
    try std.testing.expect(queues.pop(.cancellations) == null);

    try std.testing.expectEqual(@as(usize, 3), queues.pop(.completions).?.id);
    try std.testing.expectEqual(@as(usize, 4), queues.pop(.completions).?.id);
    try std.testing.expect(queues.pop(.completions) == null);

    try std.testing.expectEqual(@as(usize, 5), queues.pop(.submissions).?.id);
    try std.testing.expectEqual(@as(usize, 6), queues.pop(.submissions).?.id);
    try std.testing.expect(queues.pop(.submissions) == null);

    try std.testing.expect(queues.empty(.cancellations));
    try std.testing.expect(queues.empty(.completions));
    try std.testing.expect(queues.empty(.submissions));
}
