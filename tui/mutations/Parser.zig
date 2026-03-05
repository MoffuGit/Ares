const std = @import("std");
const Allocator = std.mem.Allocator;
const json = std.json;

const Style = @import("../window/element/Style.zig").Style;

pub const CmdType = enum(u8) {
    create = 0,
    set_props = 1,
    append_child = 2,
    insert_before = 3,
    remove_child = 4,
    delete = 5,
    set_root = 6,
    set_focus = 7,
    request_draw = 8,
};

pub const ElementType = enum(u8) {
    box = 0,
};

pub const TextAlign = enum {
    left,
    center,
    right,
    justify,
};

pub const EdgeValues = struct {
    left: ?Style.StyleValue = null,
    top: ?Style.StyleValue = null,
    right: ?Style.StyleValue = null,
    bottom: ?Style.StyleValue = null,
    start: ?Style.StyleValue = null,
    end: ?Style.StyleValue = null,
    horizontal: ?Style.StyleValue = null,
    vertical: ?Style.StyleValue = null,
    all: ?Style.StyleValue = null,
};

pub const BorderEdgeValues = struct {
    left: ?f32 = null,
    top: ?f32 = null,
    right: ?f32 = null,
    bottom: ?f32 = null,
    start: ?f32 = null,
    end: ?f32 = null,
    horizontal: ?f32 = null,
    vertical: ?f32 = null,
    all: ?f32 = null,
};

pub const GapValues = struct {
    column: ?Style.StyleValue = null,
    row: ?Style.StyleValue = null,
    all: ?Style.StyleValue = null,
};

pub const StylePatch = struct {
    direction: ?Style.Direction = null,
    flex_direction: ?Style.FlexDirection = null,
    justify_content: ?Style.Justify = null,
    align_content: ?Style.Align = null,
    align_items: ?Style.Align = null,
    align_self: ?Style.Align = null,
    position_type: ?Style.PositionType = null,
    flex_wrap: ?Style.Wrap = null,
    overflow: ?Style.Overflow = null,
    display: ?Style.Display = null,
    box_sizing: ?Style.BoxSizing = null,

    flex: ?f32 = null,
    flex_grow: ?f32 = null,
    flex_shrink: ?f32 = null,
    flex_basis: ?Style.StyleValue = null,

    width: ?Style.StyleValue = null,
    height: ?Style.StyleValue = null,
    min_width: ?Style.StyleValue = null,
    min_height: ?Style.StyleValue = null,
    max_width: ?Style.StyleValue = null,
    max_height: ?Style.StyleValue = null,

    aspect_ratio: ?f32 = null,

    position: ?EdgeValues = null,
    margin: ?EdgeValues = null,
    padding: ?EdgeValues = null,
    border: ?BorderEdgeValues = null,

    gap: ?GapValues = null,
};

pub const BoxProps = struct {
    opacity: ?f32 = null,
    text_align: ?TextAlign = null,
    rounded: ?f32 = null,
};

pub const Props = struct {
    z_index: ?usize = null,
    style: ?StylePatch = null,
    box: ?BoxProps = null,
};

pub const Command = union(CmdType) {
    create: struct { id: u64, element_type: ElementType },
    set_props: struct { id: u64, props: Props },
    append_child: struct { id: u64, child_id: u64 },
    insert_before: struct { id: u64, child_id: u64, before_id: u64 },
    remove_child: struct { id: u64, child_id: u64 },
    delete: struct { id: u64 },
    set_root: struct { id: u64 },
    set_focus: struct { id: u64 },
    request_draw: void,
};

pub const Error = error{
    not_array,
    not_object,
    missing_cmd,
    missing_id,
    missing_element_type,
    missing_child_id,
    missing_before_id,
};

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

            if (cmd_type == .request_draw) {
                return .request_draw;
            }

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
                .request_draw => unreachable,
            };

            return cmd;
        }
        return null;
    }
};

pub fn parse(alloc: Allocator, data: []const u8) ?struct { parsed: json.Parsed(json.Value), iter: Iterator } {
    const parsed = json.parseFromSlice(json.Value, alloc, data, .{}) catch return null;

    const items = switch (parsed.value) {
        .array => |arr| arr.items,
        else => {
            parsed.deinit();
            return null;
        },
    };

    return .{ .parsed = parsed, .iter = .{ .items = items } };
}

// ---- Props parsing ----

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

    return if (has_any) bp else null;
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
