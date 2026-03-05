const std = @import("std");
const testing = std.testing;
const Parser = @import("mutations/Parser.zig");
const Style = @import("window/element/Style.zig").Style;

fn parseSingle(data: []const u8) ?union(enum) { ok: Parser.Command, err: Parser.Error } {
    const result = Parser.parse(testing.allocator, data) orelse return null;
    defer result.parsed.deinit();
    var iter = result.iter;
    return iter.next();
}

fn expectCmd(data: []const u8) Parser.Command {
    const r = parseSingle(data) orelse unreachable;
    return switch (r) {
        .ok => |cmd| cmd,
        .err => unreachable,
    };
}

fn expectErr(data: []const u8) Parser.Error {
    const r = parseSingle(data) orelse unreachable;
    return switch (r) {
        .ok => unreachable,
        .err => |e| e,
    };
}

// ---- Basic command parsing ----

test "parse create command" {
    const cmd = expectCmd(
        \\[{"cmd": 0, "id": 42, "element_type": 0}]
    );
    switch (cmd) {
        .create => |c| {
            try testing.expectEqual(@as(u64, 42), c.id);
            try testing.expectEqual(Parser.ElementType.box, c.element_type);
        },
        else => return error.UnexpectedCommand,
    }
}

test "parse create command with string enum" {
    const cmd = expectCmd(
        \\[{"cmd": "create", "id": 1, "element_type": "box"}]
    );
    switch (cmd) {
        .create => |c| {
            try testing.expectEqual(@as(u64, 1), c.id);
            try testing.expectEqual(Parser.ElementType.box, c.element_type);
        },
        else => return error.UnexpectedCommand,
    }
}

test "parse delete command" {
    const cmd = expectCmd(
        \\[{"cmd": 5, "id": 99}]
    );
    switch (cmd) {
        .delete => |c| try testing.expectEqual(@as(u64, 99), c.id),
        else => return error.UnexpectedCommand,
    }
}

test "parse set_root command" {
    const cmd = expectCmd(
        \\[{"cmd": "set_root", "id": 10}]
    );
    switch (cmd) {
        .set_root => |c| try testing.expectEqual(@as(u64, 10), c.id),
        else => return error.UnexpectedCommand,
    }
}

test "parse set_focus command" {
    const cmd = expectCmd(
        \\[{"cmd": "set_focus", "id": 7}]
    );
    switch (cmd) {
        .set_focus => |c| try testing.expectEqual(@as(u64, 7), c.id),
        else => return error.UnexpectedCommand,
    }
}

test "parse request_draw command (no id required)" {
    const cmd = expectCmd(
        \\[{"cmd": 8}]
    );
    switch (cmd) {
        .request_draw => {},
        else => return error.UnexpectedCommand,
    }
}

test "parse append_child command" {
    const cmd = expectCmd(
        \\[{"cmd": 2, "id": 1, "child_id": 5}]
    );
    switch (cmd) {
        .append_child => |c| {
            try testing.expectEqual(@as(u64, 1), c.id);
            try testing.expectEqual(@as(u64, 5), c.child_id);
        },
        else => return error.UnexpectedCommand,
    }
}

test "parse insert_before command" {
    const cmd = expectCmd(
        \\[{"cmd": 3, "id": 1, "child_id": 5, "before_id": 3}]
    );
    switch (cmd) {
        .insert_before => |c| {
            try testing.expectEqual(@as(u64, 1), c.id);
            try testing.expectEqual(@as(u64, 5), c.child_id);
            try testing.expectEqual(@as(u64, 3), c.before_id);
        },
        else => return error.UnexpectedCommand,
    }
}

test "parse remove_child command" {
    const cmd = expectCmd(
        \\[{"cmd": 4, "id": 1, "child_id": 9}]
    );
    switch (cmd) {
        .remove_child => |c| {
            try testing.expectEqual(@as(u64, 1), c.id);
            try testing.expectEqual(@as(u64, 9), c.child_id);
        },
        else => return error.UnexpectedCommand,
    }
}

// ---- Error cases ----

test "error: not a json array" {
    const result = Parser.parse(testing.allocator,
        \\{"cmd": 0}
    );
    try testing.expect(result == null);
}

test "error: command is not an object" {
    const e = expectErr(
        \\[123]
    );
    try testing.expectEqual(Parser.Error.not_object, e);
}

test "error: missing cmd field" {
    const e = expectErr(
        \\[{"id": 1}]
    );
    try testing.expectEqual(Parser.Error.missing_cmd, e);
}

test "error: missing id field" {
    const e = expectErr(
        \\[{"cmd": 0}]
    );
    try testing.expectEqual(Parser.Error.missing_id, e);
}

test "error: create missing element_type" {
    const e = expectErr(
        \\[{"cmd": 0, "id": 1}]
    );
    try testing.expectEqual(Parser.Error.missing_element_type, e);
}

test "error: append_child missing child_id" {
    const e = expectErr(
        \\[{"cmd": 2, "id": 1}]
    );
    try testing.expectEqual(Parser.Error.missing_child_id, e);
}

test "error: insert_before missing before_id" {
    const e = expectErr(
        \\[{"cmd": 3, "id": 1, "child_id": 5}]
    );
    try testing.expectEqual(Parser.Error.missing_before_id, e);
}

// ---- Iterator: multiple commands ----

test "iterate multiple commands" {
    const data =
        \\[
        \\  {"cmd": 0, "id": 1, "element_type": 0},
        \\  {"cmd": 6, "id": 1},
        \\  {"cmd": 8}
        \\]
    ;
    const result = Parser.parse(testing.allocator, data) orelse return error.ParseFailed;
    defer result.parsed.deinit();
    var iter = result.iter;

    // First: create
    const c1 = (iter.next() orelse return error.UnexpectedEnd).ok;
    try testing.expectEqual(Parser.CmdType.create, c1);

    // Second: set_root
    const c2 = (iter.next() orelse return error.UnexpectedEnd).ok;
    try testing.expectEqual(Parser.CmdType.set_root, c2);

    // Third: request_draw
    const c3 = (iter.next() orelse return error.UnexpectedEnd).ok;
    try testing.expectEqual(Parser.CmdType.request_draw, c3);

    // Done
    try testing.expect(iter.next() == null);
}

// ---- Props parsing ----

test "parse set_props with z_index" {
    const cmd = expectCmd(
        \\[{"cmd": 1, "id": 5, "props": {"zIndex": 3}}]
    );
    switch (cmd) {
        .set_props => |c| {
            try testing.expectEqual(@as(u64, 5), c.id);
            try testing.expectEqual(@as(?usize, 3), c.props.z_index);
        },
        else => return error.UnexpectedCommand,
    }
}

test "parse set_props with box props" {
    const cmd = expectCmd(
        \\[{"cmd": 1, "id": 2, "props": {"opacity": 0.5, "text_align": "center"}}]
    );
    switch (cmd) {
        .set_props => |c| {
            const bp = c.props.box orelse return error.MissingBoxProps;
            try testing.expectApproxEqAbs(@as(f32, 0.5), bp.opacity.?, 0.001);
            try testing.expectEqual(Parser.TextAlign.center, bp.text_align.?);
        },
        else => return error.UnexpectedCommand,
    }
}

test "parse set_props with style patch" {
    const cmd = expectCmd(
        \\[{"cmd": 1, "id": 1, "props": {"style": {
        \\  "flex_direction": "row",
        \\  "flex_grow": 1,
        \\  "width": 100,
        \\  "height": "auto"
        \\}}}]
    );
    switch (cmd) {
        .set_props => |c| {
            const style = c.props.style orelse return error.MissingStyle;
            try testing.expectEqual(Style.FlexDirection.row, style.flex_direction.?);
            try testing.expectApproxEqAbs(@as(f32, 1.0), style.flex_grow.?, 0.001);
            try testing.expectEqual(Style.StyleValue{ .point = 100.0 }, style.width.?);
            try testing.expectEqual(Style.StyleValue.auto, style.height.?);
        },
        else => return error.UnexpectedCommand,
    }
}

test "parse set_props with percent style value" {
    const cmd = expectCmd(
        \\[{"cmd": 1, "id": 1, "props": {"style": {
        \\  "width": {"percent": 50}
        \\}}}]
    );
    switch (cmd) {
        .set_props => |c| {
            const style = c.props.style orelse return error.MissingStyle;
            try testing.expectEqual(Style.StyleValue{ .percent = 50.0 }, style.width.?);
        },
        else => return error.UnexpectedCommand,
    }
}

test "parse set_props with edge values (margin)" {
    const cmd = expectCmd(
        \\[{"cmd": 1, "id": 1, "props": {"style": {
        \\  "margin": {"left": 10, "top": 20, "all": "auto"}
        \\}}}]
    );
    switch (cmd) {
        .set_props => |c| {
            const style = c.props.style orelse return error.MissingStyle;
            const margin = style.margin orelse return error.MissingMargin;
            try testing.expectEqual(Style.StyleValue{ .point = 10.0 }, margin.left.?);
            try testing.expectEqual(Style.StyleValue{ .point = 20.0 }, margin.top.?);
            try testing.expectEqual(Style.StyleValue.auto, margin.all.?);
            try testing.expect(margin.right == null);
        },
        else => return error.UnexpectedCommand,
    }
}

test "parse set_props with border edge values" {
    const cmd = expectCmd(
        \\[{"cmd": 1, "id": 1, "props": {"style": {
        \\  "border": {"all": 2, "left": 1.5}
        \\}}}]
    );
    switch (cmd) {
        .set_props => |c| {
            const style = c.props.style orelse return error.MissingStyle;
            const border = style.border orelse return error.MissingBorder;
            try testing.expectApproxEqAbs(@as(f32, 2.0), border.all.?, 0.001);
            try testing.expectApproxEqAbs(@as(f32, 1.5), border.left.?, 0.001);
            try testing.expect(border.top == null);
        },
        else => return error.UnexpectedCommand,
    }
}

test "parse set_props with gap values" {
    const cmd = expectCmd(
        \\[{"cmd": 1, "id": 1, "props": {"style": {
        \\  "gap": {"column": 8, "row": {"percent": 5}}
        \\}}}]
    );
    switch (cmd) {
        .set_props => |c| {
            const style = c.props.style orelse return error.MissingStyle;
            const gap = style.gap orelse return error.MissingGap;
            try testing.expectEqual(Style.StyleValue{ .point = 8.0 }, gap.column.?);
            try testing.expectEqual(Style.StyleValue{ .percent = 5.0 }, gap.row.?);
            try testing.expect(gap.all == null);
        },
        else => return error.UnexpectedCommand,
    }
}

test "parse set_props with no props field" {
    const cmd = expectCmd(
        \\[{"cmd": 1, "id": 1}]
    );
    switch (cmd) {
        .set_props => |c| {
            try testing.expect(c.props.z_index == null);
            try testing.expect(c.props.style == null);
            try testing.expect(c.props.box == null);
        },
        else => return error.UnexpectedCommand,
    }
}

// ---- Parsing helpers ----

test "parseU64 with integer" {
    try testing.expectEqual(@as(?u64, 42), Parser.parseU64(.{ .integer = 42 }));
}

test "parseU64 with negative" {
    try testing.expectEqual(@as(?u64, null), Parser.parseU64(.{ .integer = -1 }));
}

test "parseU64 with float" {
    try testing.expectEqual(@as(?u64, 10), Parser.parseU64(.{ .float = 10.0 }));
}

test "parseU64 with null" {
    try testing.expectEqual(@as(?u64, null), Parser.parseU64(null));
}

test "parseF32 with float" {
    try testing.expectApproxEqAbs(@as(f32, 3.14), Parser.parseF32(.{ .float = 3.14 }).?, 0.01);
}

test "parseF32 with integer" {
    try testing.expectApproxEqAbs(@as(f32, 5.0), Parser.parseF32(.{ .integer = 5 }).?, 0.001);
}

test "parseStyleValue with string keywords" {
    try testing.expectEqual(Style.StyleValue.auto, Parser.parseStyleValue(.{ .string = "auto" }).?);
    try testing.expectEqual(Style.StyleValue.undefined, Parser.parseStyleValue(.{ .string = "undefined" }).?);
    try testing.expectEqual(Style.StyleValue.stretch, Parser.parseStyleValue(.{ .string = "stretch" }).?);
    try testing.expect(Parser.parseStyleValue(.{ .string = "bogus" }) == null);
}

test "parseStyleValue with integer" {
    try testing.expectEqual(Style.StyleValue{ .point = 50.0 }, Parser.parseStyleValue(.{ .integer = 50 }).?);
}

test "parseEnum with string" {
    try testing.expectEqual(Parser.CmdType.create, Parser.parseEnum(Parser.CmdType, .{ .string = "create" }).?);
}

test "parseEnum with integer" {
    try testing.expectEqual(Parser.CmdType.delete, Parser.parseEnum(Parser.CmdType, .{ .integer = 5 }).?);
}

test "parseEnum with invalid string" {
    try testing.expect(Parser.parseEnum(Parser.CmdType, .{ .string = "nonexistent" }) == null);
}
