const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.mutations);

const Element = @import("../window/element/mod.zig");
const Style = Element.Style;
const Node = Element.Node;
const Box = @import("../window/element/Box.zig");
const Window = @import("../window/mod.zig");
const App = @import("../App.zig");

const MutationQueue = @This();

const json = std.json;

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

pub fn processBatch(app: *App, data: []const u8) void {
    const alloc = app.alloc;
    const window = &app.window;

    const parsed = json.parseFromSlice(json.Value, alloc, data, .{}) catch |err| {
        log.err("failed to parse mutation batch JSON: {}", .{err});
        return;
    };
    defer parsed.deinit();

    const cmds = switch (parsed.value) {
        .array => |arr| arr.items,
        else => {
            log.err("mutation batch must be a JSON array", .{});
            return;
        },
    };

    for (cmds) |cmd_val| {
        const obj = switch (cmd_val) {
            .object => |o| o,
            else => {
                log.err("each command must be a JSON object", .{});
                continue;
            },
        };

        const cmd_type = parseEnum(CmdType, obj.get("cmd")) orelse {
            log.err("missing or invalid 'cmd' field", .{});
            continue;
        };

        const id = parseU64(obj.get("id")) orelse if (cmd_type != .request_draw) {
            log.err("missing or invalid 'id' field", .{});
            continue;
        } else 0;

        switch (cmd_type) {
            .create => handleCreate(alloc, window, id, obj),
            .set_props => handleSetProps(window, id, obj),
            .append_child => handleAppendChild(window, id, obj),
            .insert_before => handleInsertBefore(window, id, obj),
            .remove_child => handleRemoveChild(window, id, obj),
            .delete => handleDelete(alloc, window, id),
            .set_root => handleSetRoot(window, id),
            .set_focus => window.setFocus(id),
            .request_draw => app.requestDraw(),
        }
    }
}

// ---- Command handlers ----

fn handleCreate(alloc: Allocator, window: *Window, id: u64, obj: json.ObjectMap) void {
    const elem_type = parseEnum(ElementType, obj.get("element_type")) orelse {
        log.err("create: missing or invalid 'element_type' for id={}", .{id});
        return;
    };

    switch (elem_type) {
        .box => createBox(alloc, window, id),
    }
}

fn createBox(alloc: Allocator, window: *Window, id: u64) void {
    const box = Box.init(alloc, .{ .num = id }) catch |err| {
        log.err("create box id={}: {}", .{ id, err });
        return;
    };
    window.addElement(box.elem()) catch |err| {
        log.err("register box id={}: {}", .{ id, err });
        box.deinit(alloc);
    };
}

fn handleSetProps(window: *Window, id: u64, obj: json.ObjectMap) void {
    const elem = window.getElement(id) orelse {
        log.err("set_props: unknown element id={}", .{id});
        return;
    };

    const props = switch (obj.get("props") orelse return) {
        .object => |o| o,
        else => return,
    };

    // Apply common props
    if (props.get("zIndex")) |v| {
        if (parseUsize(v)) |z| elem.zIndex = z;
    }

    if (props.get("style")) |style_val| {
        switch (style_val) {
            .object => |style_obj| applyStylePatch(elem, style_obj),
            else => {},
        }
    }

    // Apply type-specific props
    switch (elem.kind) {
        .box => applyBoxProps(elem, props),
        .raw => {},
    }
}

fn handleAppendChild(window: *Window, parent_id: u64, obj: json.ObjectMap) void {
    const child_id = parseU64(obj.get("child_id")) orelse {
        log.err("append_child: missing 'child_id'", .{});
        return;
    };

    const parent = window.getElement(parent_id) orelse {
        log.err("append_child: unknown parent id={}", .{parent_id});
        return;
    };
    const child = window.getElement(child_id) orelse {
        log.err("append_child: unknown child id={}", .{child_id});
        return;
    };

    parent.addChild(child) catch |err| {
        log.err("append_child: parent={} child={}: {}", .{ parent_id, child_id, err });
    };
}

fn handleInsertBefore(window: *Window, parent_id: u64, obj: json.ObjectMap) void {
    const child_id = parseU64(obj.get("child_id")) orelse {
        log.err("insert_before: missing 'child_id'", .{});
        return;
    };
    const before_id = parseU64(obj.get("before_id")) orelse {
        log.err("insert_before: missing 'before_id'", .{});
        return;
    };

    const parent = window.getElement(parent_id) orelse {
        log.err("insert_before: unknown parent id={}", .{parent_id});
        return;
    };
    const child = window.getElement(child_id) orelse {
        log.err("insert_before: unknown child id={}", .{child_id});
        return;
    };

    // Find the index of before_id in parent's children
    const index = blk: {
        if (parent.childrens) |*childrens| {
            for (childrens.by_order.items, 0..) |c, i| {
                if (c.num == before_id) break :blk i;
            }
        }
        log.err("insert_before: before_id={} not found in parent={}", .{ before_id, parent_id });
        return;
    };

    parent.insertChild(child, index) catch |err| {
        log.err("insert_before: parent={} child={} before={}: {}", .{ parent_id, child_id, before_id, err });
    };
}

fn handleRemoveChild(window: *Window, parent_id: u64, obj: json.ObjectMap) void {
    const child_id = parseU64(obj.get("child_id")) orelse {
        log.err("remove_child: missing 'child_id'", .{});
        return;
    };

    const parent = window.getElement(parent_id) orelse {
        log.err("remove_child: unknown parent id={}", .{parent_id});
        return;
    };

    parent.removeChild(child_id);
}

fn handleDelete(alloc: Allocator, window: *Window, id: u64) void {
    const elem = window.getElement(id) orelse return;

    // Remove from parent if still attached
    if (elem.parent) |parent| {
        parent.removeChild(id);
    }

    window.removeElement(id);

    // Cleanup based on kind
    switch (elem.kind) {
        .box => {
            const box: *Box = @ptrCast(@alignCast(elem.userdata orelse return));
            box.deinit(alloc);
        },
        .raw => {
            elem.deinit();
            alloc.destroy(elem);
        },
    }
}

fn handleSetRoot(window: *Window, id: u64) void {
    const elem = window.getElement(id) orelse {
        log.err("set_root: unknown element id={}", .{id});
        return;
    };
    window.setRoot(elem);
}

// ---- Type-specific prop application ----

fn applyBoxProps(elem: *Element, props: json.ObjectMap) void {
    const box: *Box = @ptrCast(@alignCast(elem.userdata orelse return));

    if (props.get("opacity")) |v| {
        if (parseF32(v)) |f| box.opacity = f;
    }
    if (props.get("text_align")) |v| {
        if (parseEnum(Element.TextAlign, v)) |ta| box.text_align = ta;
    }
    if (props.get("rounded")) |v| {
        box.rounded = parseF32(v);
    }
}

fn applyStylePatch(elem: *Element, obj: json.ObjectMap) void {
    const node = elem.node;

    if (obj.get("direction")) |v| {
        if (parseEnum(Style.Direction, v)) |d| {
            elem.style.direction = d;
            node.setDirection(d);
        }
    }
    if (obj.get("flex_direction")) |v| {
        if (parseEnum(Style.FlexDirection, v)) |d| {
            elem.style.flex_direction = d;
            node.setFlexDirection(d);
        }
    }
    if (obj.get("justify_content")) |v| {
        if (parseEnum(Style.Justify, v)) |d| {
            elem.style.justify_content = d;
            node.setJustifyContent(d);
        }
    }
    if (obj.get("align_content")) |v| {
        if (parseEnum(Style.Align, v)) |d| {
            elem.style.align_content = d;
            node.setAlignContent(d);
        }
    }
    if (obj.get("align_items")) |v| {
        if (parseEnum(Style.Align, v)) |d| {
            elem.style.align_items = d;
            node.setAlignItems(d);
        }
    }
    if (obj.get("align_self")) |v| {
        if (parseEnum(Style.Align, v)) |d| {
            elem.style.align_self = d;
            node.setAlignSelf(d);
        }
    }
    if (obj.get("position_type")) |v| {
        if (parseEnum(Style.PositionType, v)) |d| {
            elem.style.position_type = d;
            node.setPositionType(d);
        }
    }
    if (obj.get("flex_wrap")) |v| {
        if (parseEnum(Style.Wrap, v)) |d| {
            elem.style.flex_wrap = d;
            node.setFlexWrap(d);
        }
    }
    if (obj.get("overflow")) |v| {
        if (parseEnum(Style.Overflow, v)) |d| {
            elem.style.overflow = d;
            node.setOverflow(d);
        }
    }
    if (obj.get("display")) |v| {
        if (parseEnum(Style.Display, v)) |d| {
            elem.style.display = d;
            node.setDisplay(d);
        }
    }
    if (obj.get("box_sizing")) |v| {
        if (parseEnum(Style.BoxSizing, v)) |d| {
            elem.style.box_sizing = d;
            node.setBoxSizing(d);
        }
    }

    // Flex scalars
    if (obj.get("flex")) |v| {
        if (parseF32(v)) |f| {
            elem.style.flex = f;
            node.setFlex(f);
        }
    }
    if (obj.get("flex_grow")) |v| {
        if (parseF32(v)) |f| {
            elem.style.flex_grow = f;
            node.setFlexGrow(f);
        }
    }
    if (obj.get("flex_shrink")) |v| {
        if (parseF32(v)) |f| {
            elem.style.flex_shrink = f;
            node.setFlexShrink(f);
        }
    }
    if (obj.get("flex_basis")) |v| {
        if (parseStyleValue(v)) |sv| {
            elem.style.flex_basis = sv;
            node.setFlexBasis(sv);
        }
    }

    // Dimensions
    if (obj.get("width")) |v| {
        if (parseStyleValue(v)) |sv| {
            elem.style.width = sv;
            node.setWidth(sv);
        }
    }
    if (obj.get("height")) |v| {
        if (parseStyleValue(v)) |sv| {
            elem.style.height = sv;
            node.setHeight(sv);
        }
    }
    if (obj.get("min_width")) |v| {
        if (parseStyleValue(v)) |sv| {
            elem.style.min_width = sv;
            node.setMinWidth(sv);
        }
    }
    if (obj.get("min_height")) |v| {
        if (parseStyleValue(v)) |sv| {
            elem.style.min_height = sv;
            node.setMinHeight(sv);
        }
    }
    if (obj.get("max_width")) |v| {
        if (parseStyleValue(v)) |sv| {
            elem.style.max_width = sv;
            node.setMaxWidth(sv);
        }
    }
    if (obj.get("max_height")) |v| {
        if (parseStyleValue(v)) |sv| {
            elem.style.max_height = sv;
            node.setMaxHeight(sv);
        }
    }

    if (obj.get("aspect_ratio")) |v| {
        if (parseF32(v)) |f| {
            elem.style.aspect_ratio = f;
            node.setAspectRatio(f);
        }
    }

    // Edge-based properties
    if (obj.get("position")) |v| {
        switch (v) {
            .object => |eo| applyEdgePatch(&elem.style.position, node, Node.setPosition, eo),
            else => {},
        }
    }
    if (obj.get("margin")) |v| {
        switch (v) {
            .object => |eo| applyEdgePatch(&elem.style.margin, node, Node.setMargin, eo),
            else => {},
        }
    }
    if (obj.get("padding")) |v| {
        switch (v) {
            .object => |eo| applyEdgePatch(&elem.style.padding, node, Node.setPadding, eo),
            else => {},
        }
    }
    if (obj.get("border")) |v| {
        switch (v) {
            .object => |eo| applyBorderEdgePatch(&elem.style.border, node, eo),
            else => {},
        }
    }

    // Gap
    if (obj.get("gap")) |v| {
        switch (v) {
            .object => |go| applyGapPatch(&elem.style.gap, node, go),
            else => {},
        }
    }
}

fn applyEdgePatch(edges: *Style.Edges, node: Node, setter: *const fn (Node, Style.Edge, Style.StyleValue) void, obj: json.ObjectMap) void {
    const edge_names = .{
        .{ "left", Style.Edge.left, &edges.left },
        .{ "top", Style.Edge.top, &edges.top },
        .{ "right", Style.Edge.right, &edges.right },
        .{ "bottom", Style.Edge.bottom, &edges.bottom },
        .{ "start", Style.Edge.start, &edges.start },
        .{ "end", Style.Edge.end, &edges.end },
        .{ "horizontal", Style.Edge.horizontal, &edges.horizontal },
        .{ "vertical", Style.Edge.vertical, &edges.vertical },
        .{ "all", Style.Edge.all, &edges.all },
    };

    inline for (edge_names) |entry| {
        if (obj.get(entry[0])) |v| {
            if (parseStyleValue(v)) |sv| {
                entry[2].* = sv;
                setter(node, entry[1], sv);
            }
        }
    }
}

fn applyBorderEdgePatch(border: *Style.BorderEdges, node: Node, obj: json.ObjectMap) void {
    const edge_names = .{
        .{ "left", Style.Edge.left, &border.left },
        .{ "top", Style.Edge.top, &border.top },
        .{ "right", Style.Edge.right, &border.right },
        .{ "bottom", Style.Edge.bottom, &border.bottom },
        .{ "start", Style.Edge.start, &border.start },
        .{ "end", Style.Edge.end, &border.end },
        .{ "horizontal", Style.Edge.horizontal, &border.horizontal },
        .{ "vertical", Style.Edge.vertical, &border.vertical },
        .{ "all", Style.Edge.all, &border.all },
    };

    inline for (edge_names) |entry| {
        if (obj.get(entry[0])) |v| {
            if (parseF32(v)) |f| {
                entry[2].* = f;
                node.setBorder(entry[1], f);
            }
        }
    }
}

fn applyGapPatch(gap: *Style.Gap, node: Node, obj: json.ObjectMap) void {
    const gap_entries = .{
        .{ "column", Style.Gutter.column, &gap.column },
        .{ "row", Style.Gutter.row, &gap.row },
        .{ "all", Style.Gutter.all, &gap.all },
    };

    inline for (gap_entries) |entry| {
        if (obj.get(entry[0])) |v| {
            if (parseStyleValue(v)) |sv| {
                entry[2].* = sv;
                node.setGap(entry[1], sv);
            }
        }
    }
}

// ---- JSON parsing helpers ----

fn parseU64(val: ?json.Value) ?u64 {
    const v = val orelse return null;
    return switch (v) {
        .integer => |i| if (i >= 0) @intCast(i) else null,
        .float => |f| if (f >= 0 and f <= @as(f64, @floatFromInt(std.math.maxInt(u64)))) @intFromFloat(f) else null,
        else => null,
    };
}

fn parseUsize(val: ?json.Value) ?usize {
    const v = val orelse return null;
    return switch (v) {
        .integer => |i| if (i >= 0) @intCast(i) else null,
        .float => |f| if (f >= 0) @intFromFloat(f) else null,
        else => null,
    };
}

fn parseF32(val: ?json.Value) ?f32 {
    const v = val orelse return null;
    return switch (v) {
        .float => |f| @floatCast(f),
        .integer => |i| @floatFromInt(i),
        else => null,
    };
}

fn parseEnum(comptime E: type, val: ?json.Value) ?E {
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

fn parseStyleValue(val: ?json.Value) ?Style.StyleValue {
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
