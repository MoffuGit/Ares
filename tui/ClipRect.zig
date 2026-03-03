const ClipRect = @This();

x: u16,
y: u16,
width: u16,
height: u16,

pub fn intersect(self: ClipRect, other: ClipRect) ?ClipRect {
    const left = @max(self.x, other.x);
    const top = @max(self.y, other.y);

    const self_right = self.x + self.width;
    const other_right = other.x + other.width;
    const right = @min(self_right, other_right);

    const self_bottom = self.y + self.height;
    const other_bottom = other.y + other.height;
    const bottom = @min(self_bottom, other_bottom);

    if (left >= right or top >= bottom) {
        return null;
    }

    return .{
        .x = left,
        .y = top,
        .width = right - left,
        .height = bottom - top,
    };
}

pub fn contains(self: ClipRect, col: u16, row: u16) bool {
    return col >= self.x and
        col < self.x + self.width and
        row >= self.y and
        row < self.y + self.height;
}

const testing = @import("std").testing;

test "intersect overlapping rects" {
    const a = ClipRect{ .x = 0, .y = 0, .width = 10, .height = 10 };
    const b = ClipRect{ .x = 5, .y = 5, .width = 10, .height = 10 };

    const result = a.intersect(b);
    try testing.expect(result != null);
    try testing.expectEqual(@as(u16, 5), result.?.x);
    try testing.expectEqual(@as(u16, 5), result.?.y);
    try testing.expectEqual(@as(u16, 5), result.?.width);
    try testing.expectEqual(@as(u16, 5), result.?.height);
}

test "intersect non-overlapping rects" {
    const a = ClipRect{ .x = 0, .y = 0, .width = 5, .height = 5 };
    const b = ClipRect{ .x = 10, .y = 10, .width = 5, .height = 5 };

    const result = a.intersect(b);
    try testing.expect(result == null);
}

test "intersect adjacent rects (no overlap)" {
    const a = ClipRect{ .x = 0, .y = 0, .width = 5, .height = 5 };
    const b = ClipRect{ .x = 5, .y = 0, .width = 5, .height = 5 };

    const result = a.intersect(b);
    try testing.expect(result == null);
}

test "intersect one inside other" {
    const outer = ClipRect{ .x = 0, .y = 0, .width = 20, .height = 20 };
    const inner = ClipRect{ .x = 5, .y = 5, .width = 5, .height = 5 };

    const result = outer.intersect(inner);
    try testing.expect(result != null);
    try testing.expectEqual(@as(u16, 5), result.?.x);
    try testing.expectEqual(@as(u16, 5), result.?.y);
    try testing.expectEqual(@as(u16, 5), result.?.width);
    try testing.expectEqual(@as(u16, 5), result.?.height);
}

test "contains point inside" {
    const rect = ClipRect{ .x = 5, .y = 5, .width = 10, .height = 10 };
    try testing.expect(rect.contains(5, 5));
    try testing.expect(rect.contains(10, 10));
    try testing.expect(rect.contains(14, 14));
}

test "contains point outside" {
    const rect = ClipRect{ .x = 5, .y = 5, .width = 10, .height = 10 };
    try testing.expect(!rect.contains(4, 5));
    try testing.expect(!rect.contains(5, 4));
    try testing.expect(!rect.contains(15, 5));
    try testing.expect(!rect.contains(5, 15));
}
