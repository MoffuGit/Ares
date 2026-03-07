const std = @import("std");
const Allocator = std.mem.Allocator;
const json = std.json;
const cmdpkg = @import("cmd.zig");
pub const Command = cmdpkg.Command;
pub const CmdType = cmdpkg.CmdType;
pub const ElementType = cmdpkg.ElementType;
const Props = cmdpkg.Props;
const BoxProps = cmdpkg.BoxProps;
pub const TextAlign = cmdpkg.TextAlign;
const StylePatch = cmdpkg.StylePatch;
const EdgeValues = cmdpkg.EdgeValues;
const BorderEdgeValues = cmdpkg.BorderEdgeValues;
const GapValues = cmdpkg.GapValues;
const ColorValue = cmdpkg.ColorValue;

const Style = @import("../window/element/Style.zig").Style;

pub const Error = error{
    not_array,
    not_object,
    missing_cmd,
    missing_id,
    missing_element_type,
    missing_child_id,
    missing_before_id,
};

const Parser = @This();

parsed: json.Parsed(json.Value),

pub const Iterator = struct {
    items: []const json.Value,
    index: usize = 0,

    pub fn next(self: *Iterator) ?Error!Command {
        while (self.index < self.items.len) {
            const val = self.items[self.index];
            self.index += 1;

            const obj = switch (val) {
                .object => |o| o,
                else => return error.not_object,
            };

            const cmd_type = parseEnum(CmdType, obj.get("cmd")) orelse
                return error.missing_cmd;

            const id = parseU64(obj.get("id")) orelse
                return error.missing_id;

            const cmd: Command = switch (cmd_type) {
                .create => blk: {
                    const elem_type = parseEnum(ElementType, obj.get("element_type")) orelse
                        return error.missing_element_type;
                    break :blk .{ .create = .{ .id = id, .element_type = elem_type } };
                },
                .set_props => .{ .set_props = .{ .id = id, .props = parseProps(obj) } },
                .append_child => blk: {
                    const child_id = parseU64(obj.get("child_id")) orelse
                        return error.missing_child_id;
                    break :blk .{ .append_child = .{ .id = id, .child_id = child_id } };
                },
                .insert_before => blk: {
                    const child_id = parseU64(obj.get("child_id")) orelse
                        return error.missing_child_id;
                    const before_id = parseU64(obj.get("before_id")) orelse
                        return error.missing_before_id;
                    break :blk .{ .insert_before = .{ .id = id, .child_id = child_id, .before_id = before_id } };
                },
                .remove_child => blk: {
                    const child_id = parseU64(obj.get("child_id")) orelse
                        return error.missing_child_id;
                    break :blk .{ .remove_child = .{ .id = id, .child_id = child_id } };
                },
                .delete => .{ .delete = .{ .id = id } },
                .set_root => .{ .set_root = .{ .id = id } },
                .set_focus => .{ .set_focus = .{ .id = id } },
            };

            return cmd;
        }
        return null;
    }
};

pub fn parse(alloc: Allocator, data: []const u8) !Parser {
    const parsed = try json.parseFromSlice(json.Value, alloc, data, .{});

    return .{ .parsed = parsed };
}

pub fn iter(self: *Parser) !Iterator {
    const items = switch (self.parsed.value) {
        .array => |arr| arr.items,
        else => return error.not_array,
    };
    return .{ .index = 0, .items = items };
}

pub fn deinit(self: *Parser) void {
    self.parsed.deinit();
}

fn parseProps(obj: json.ObjectMap) Props {
    var result = Props{};

    const props = switch (obj.get("props") orelse return result) {
        .object => |o| o,
        else => return result,
    };

    if (props.get("zIndex")) |v| {
        result.z_index = parseUsize(v);
    }

    if (props.get("style")) |v| {
        switch (v) {
            .object => |style_obj| result.style = parseStylePatch(style_obj),
            else => {},
        }
    }

    result.box = parseBoxProps(props);

    return result;
}

fn parseBoxProps(props: json.ObjectMap) ?BoxProps {
    var bp = BoxProps{};
    var has_any = false;

    if (props.get("opacity")) |v| {
        bp.opacity = parseF32(v);
        if (bp.opacity != null) has_any = true;
    }
    if (props.get("text_align")) |v| {
        bp.text_align = parseEnum(TextAlign, v);
        if (bp.text_align != null) has_any = true;
    }
    if (props.get("rounded")) |v| {
        bp.rounded = parseF32(v);
        if (bp.rounded != null) has_any = true;
    }

    if (props.get("bg")) |bg| {
        bp.bg = parseColor(bg);
    }

    if (props.get("fg")) |fg| {
        bp.fg = parseColor(fg);
    }

    return if (has_any) bp else null;
}

fn parseColor(color: json.Value) ?ColorValue {
    _ = color;
    return null;
}

fn parseStylePatch(obj: json.ObjectMap) StylePatch {
    var s = StylePatch{};

    // Enum properties
    if (obj.get("direction")) |v| s.direction = parseEnum(Style.Direction, v);
    if (obj.get("flex_direction")) |v| s.flex_direction = parseEnum(Style.FlexDirection, v);
    if (obj.get("justify_content")) |v| s.justify_content = parseEnum(Style.Justify, v);
    if (obj.get("align_content")) |v| s.align_content = parseEnum(Style.Align, v);
    if (obj.get("align_items")) |v| s.align_items = parseEnum(Style.Align, v);
    if (obj.get("align_self")) |v| s.align_self = parseEnum(Style.Align, v);
    if (obj.get("position_type")) |v| s.position_type = parseEnum(Style.PositionType, v);
    if (obj.get("flex_wrap")) |v| s.flex_wrap = parseEnum(Style.Wrap, v);
    if (obj.get("overflow")) |v| s.overflow = parseEnum(Style.Overflow, v);
    if (obj.get("display")) |v| s.display = parseEnum(Style.Display, v);
    if (obj.get("box_sizing")) |v| s.box_sizing = parseEnum(Style.BoxSizing, v);

    // Flex scalars
    if (obj.get("flex")) |v| s.flex = parseF32(v);
    if (obj.get("flex_grow")) |v| s.flex_grow = parseF32(v);
    if (obj.get("flex_shrink")) |v| s.flex_shrink = parseF32(v);
    if (obj.get("flex_basis")) |v| s.flex_basis = parseStyleValue(v);

    // Dimensions
    if (obj.get("width")) |v| s.width = parseStyleValue(v);
    if (obj.get("height")) |v| s.height = parseStyleValue(v);
    if (obj.get("min_width")) |v| s.min_width = parseStyleValue(v);
    if (obj.get("min_height")) |v| s.min_height = parseStyleValue(v);
    if (obj.get("max_width")) |v| s.max_width = parseStyleValue(v);
    if (obj.get("max_height")) |v| s.max_height = parseStyleValue(v);

    if (obj.get("aspect_ratio")) |v| s.aspect_ratio = parseF32(v);

    // Edge-based properties
    if (obj.get("position")) |v| {
        switch (v) {
            .object => |eo| s.position = parseEdgeValues(eo),
            else => {},
        }
    }
    if (obj.get("margin")) |v| {
        switch (v) {
            .object => |eo| s.margin = parseEdgeValues(eo),
            else => {},
        }
    }
    if (obj.get("padding")) |v| {
        switch (v) {
            .object => |eo| s.padding = parseEdgeValues(eo),
            else => {},
        }
    }
    if (obj.get("border")) |v| {
        switch (v) {
            .object => |eo| s.border = parseBorderEdgeValues(eo),
            else => {},
        }
    }

    // Gap
    if (obj.get("gap")) |v| {
        switch (v) {
            .object => |go| s.gap = parseGapValues(go),
            else => {},
        }
    }

    return s;
}

fn parseEdgeValues(obj: json.ObjectMap) EdgeValues {
    var ev = EdgeValues{};
    if (obj.get("left")) |v| ev.left = parseStyleValue(v);
    if (obj.get("top")) |v| ev.top = parseStyleValue(v);
    if (obj.get("right")) |v| ev.right = parseStyleValue(v);
    if (obj.get("bottom")) |v| ev.bottom = parseStyleValue(v);
    if (obj.get("start")) |v| ev.start = parseStyleValue(v);
    if (obj.get("end")) |v| ev.end = parseStyleValue(v);
    if (obj.get("horizontal")) |v| ev.horizontal = parseStyleValue(v);
    if (obj.get("vertical")) |v| ev.vertical = parseStyleValue(v);
    if (obj.get("all")) |v| ev.all = parseStyleValue(v);
    return ev;
}

fn parseBorderEdgeValues(obj: json.ObjectMap) BorderEdgeValues {
    var ev = BorderEdgeValues{};
    if (obj.get("left")) |v| ev.left = parseF32(v);
    if (obj.get("top")) |v| ev.top = parseF32(v);
    if (obj.get("right")) |v| ev.right = parseF32(v);
    if (obj.get("bottom")) |v| ev.bottom = parseF32(v);
    if (obj.get("start")) |v| ev.start = parseF32(v);
    if (obj.get("end")) |v| ev.end = parseF32(v);
    if (obj.get("horizontal")) |v| ev.horizontal = parseF32(v);
    if (obj.get("vertical")) |v| ev.vertical = parseF32(v);
    if (obj.get("all")) |v| ev.all = parseF32(v);
    return ev;
}

fn parseGapValues(obj: json.ObjectMap) GapValues {
    var gv = GapValues{};
    if (obj.get("column")) |v| gv.column = parseStyleValue(v);
    if (obj.get("row")) |v| gv.row = parseStyleValue(v);
    if (obj.get("all")) |v| gv.all = parseStyleValue(v);
    return gv;
}

// ---- JSON parsing helpers ----

pub fn parseU64(val: ?json.Value) ?u64 {
    const v = val orelse return null;
    return switch (v) {
        .integer => |i| if (i >= 0) @intCast(i) else null,
        .float => |f| if (f >= 0 and f <= @as(f64, @floatFromInt(std.math.maxInt(u64)))) @intFromFloat(f) else null,
        else => null,
    };
}

pub fn parseUsize(val: ?json.Value) ?usize {
    const v = val orelse return null;
    return switch (v) {
        .integer => |i| if (i >= 0) @intCast(i) else null,
        .float => |f| if (f >= 0) @intFromFloat(f) else null,
        else => null,
    };
}

pub fn parseF32(val: ?json.Value) ?f32 {
    const v = val orelse return null;
    return switch (v) {
        .float => |f| @floatCast(f),
        .integer => |i| @floatFromInt(i),
        else => null,
    };
}

pub fn parseEnum(comptime E: type, val: ?json.Value) ?E {
    const v = val orelse return null;
    return switch (v) {
        .string => |s| std.meta.stringToEnum(E, s),
        .integer => |i| {
            if (i < 0) return null;
            return std.meta.intToEnum(E, @as(std.meta.Tag(E), @intCast(i))) catch null;
        },
        else => null,
    };
}

pub fn parseStyleValue(val: ?json.Value) ?Style.StyleValue {
    const v = val orelse return null;
    return switch (v) {
        .string => |s| {
            if (std.mem.eql(u8, s, "auto")) return .auto;
            if (std.mem.eql(u8, s, "undefined")) return .undefined;
            if (std.mem.eql(u8, s, "max_content")) return .max_content;
            if (std.mem.eql(u8, s, "fit_content")) return .fit_content;
            if (std.mem.eql(u8, s, "stretch")) return .stretch;
            return null;
        },
        .object => |o| {
            if (o.get("point")) |pv| {
                if (parseF32(pv)) |f| return .{ .point = f };
            }
            if (o.get("percent")) |pv| {
                if (parseF32(pv)) |f| return .{ .percent = f };
            }
            return null;
        },
        .integer => |i| .{ .point = @floatFromInt(i) },
        .float => |f| .{ .point = @floatCast(f) },
        else => null,
    };
}
const testing = std.testing;

fn expectCmd(data: []const u8) Parser.Command {
    var parser = Parser.parse(testing.allocator, data) catch unreachable;
    defer parser.deinit();
    var _iter = parser.iter() catch unreachable;
    return (_iter.next() orelse unreachable) catch unreachable;
}

fn expectErr(data: []const u8) Parser.Error {
    var parser = Parser.parse(testing.allocator, data) catch unreachable;
    defer parser.deinit();
    var _iter = parser.iter() catch unreachable;
    if (_iter.next()) |v| {
        _ = v catch |e| return e;
        unreachable;
    }
    unreachable;
}

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
    var parser = Parser.parse(testing.allocator,
        \\{"cmd": 0}
    ) catch unreachable;
    defer parser.deinit();
    const result = parser.iter();
    try testing.expectError(error.not_array, result);
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
        \\  {"cmd": 6, "id": 1}
        \\]
    ;
    var parser = Parser.parse(testing.allocator, data) catch return error.ParseFailed;
    defer parser.deinit();
    var _iter = parser.iter() catch return error.ParseFailed;

    // First: create
    const c1 = try (_iter.next() orelse return error.UnexpectedEnd);
    try testing.expect(c1 == .create);

    // Second: set_root
    const c2 = try (_iter.next() orelse return error.UnexpectedEnd);
    try testing.expect(c2 == .set_root);

    // Done
    try testing.expect(_iter.next() == null);
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
