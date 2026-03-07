const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.mutations);

const Parser = @import("Parser.zig");
const cmdpkg = @import("cmd.zig");
const Command = cmdpkg.Command;
const Element = @import("../window/element/mod.zig");
const Style = Element.Style;
const Node = Element.Node;
const Box = @import("../window/element/Box.zig");
const Window = @import("../window/mod.zig");

const Mutations = @This();
alloc: Allocator,
window: *Window,

pub fn create(alloc: Allocator, window: *Window) !*Mutations {
    const mutations = try alloc.create(Mutations);
    mutations.* = .{
        .alloc = alloc,
        .window = window,
    };

    return mutations;
}

pub fn destroy(self: *Mutations) void {
    self.alloc.destroy(self);
}

pub fn processMutations(self: *Mutations, data: []const u8) void {
    var parser = Parser.parse(self.alloc, data) catch |err| {
        log.err("parse mutations: {}", .{err});
        return;
    };
    defer parser.deinit();

    var iter = parser.iter() catch |err| {
        log.err("iter mutations: {}", .{err});
        return;
    };

    while (iter.next()) |maybe| {
        const cmd = maybe catch continue;
        switch (cmd) {
            .create => self.createCmd(cmd),
            .set_props => self.setProps(cmd),
            .append_child => self.appendChild(cmd),
            .insert_before => self.insertBefore(cmd),
            .set_root => |d| self.setRoot(d.id),
            .delete => |d| self.delete(d.id),
            .remove_child => self.removeChild(cmd),
            .set_focus => |d| self.window.setFocus(d.id),
        }
    }
}

fn createCmd(self: *Mutations, cmd: Command) void {
    const data = cmd.create;

    switch (data.element_type) {
        .box => {
            const box = Box.init(self.alloc, .{ .num = data.id }) catch |err| {
                log.err("create box id={}: {}", .{ data.id, err });
                return;
            };
            self.window.addElement(box.elem()) catch |err| {
                log.err("register box id={}: {}", .{ data.id, err });
                box.deinit(self.alloc);
            };
        },
    }
}

fn setProps(self: *Mutations, cmd: Command) void {
    const data = cmd.set_props;
    const elem = self.window.getElement(data.id) orelse {
        log.err("set_props: unknown element id={}", .{data.id});
        return;
    };
    const props = data.props;

    if (props.z_index) |z| {
        elem.zIndex = z;
    }

    if (props.style) |style| {
        applyStylePatch(elem, style);
    }

    if (props.box) |box_props| {
        applyBoxProps(elem, box_props);
    }
}

fn appendChild(self: *Mutations, cmd: Command) void {
    const data = cmd.append_child;
    const window = self.window;

    const parent = window.getElement(data.id) orelse {
        log.err("append_child: unknown parent id={}", .{data.id});
        return;
    };
    const child = window.getElement(data.child_id) orelse {
        log.err("append_child: unknown child id={}", .{data.child_id});
        return;
    };

    parent.addChild(child) catch |err| {
        log.err("append_child: parent={} child={}: {}", .{ data.id, data.child_id, err });
    };
}

fn insertBefore(self: *Mutations, cmd: Command) void {
    const data = cmd.insert_before;
    const window = self.window;

    const parent = window.getElement(data.id) orelse {
        log.err("insert_before: unknown parent id={}", .{data.id});
        return;
    };
    const child = window.getElement(data.child_id) orelse {
        log.err("insert_before: unknown child id={}", .{data.child_id});
        return;
    };

    const index = blk: {
        if (parent.childrens) |*childrens| {
            for (childrens.by_order.items, 0..) |c, i| {
                if (c.num == data.before_id) break :blk i;
            }
        }
        log.err("insert_before: before_id={} not found in parent={}", .{ data.before_id, data.id });
        return;
    };

    parent.insertChild(child, index) catch |err| {
        log.err("insert_before: parent={} child={} before={}: {}", .{ data.id, data.child_id, data.before_id, err });
    };
}

fn removeChild(self: *Mutations, cmd: Command) void {
    const data = cmd.remove_child;

    const parent = self.window.getElement(data.id) orelse {
        log.err("remove_child: unknown parent id={}", .{data.id});
        return;
    };

    parent.removeChild(data.child_id);
}

fn delete(self: *Mutations, id: u64) void {
    const window = self.window;
    const elem = window.getElement(id) orelse return;

    if (elem.parent) |parent| {
        parent.removeChild(id);
    }

    window.removeElement(id);

    switch (elem.kind) {
        .box => {
            const box: *Box = @ptrCast(@alignCast(elem.userdata orelse return));
            box.deinit(self.alloc);
        },
        .raw => {
            elem.deinit();
            self.alloc.destroy(elem);
        },
    }
}

fn setRoot(self: *Mutations, id: u64) void {
    const elem = self.window.getElement(id) orelse {
        log.err("set_root: unknown element id={}", .{id});
        return;
    };
    self.window.setRoot(elem);
}

fn applyBoxProps(elem: *Element, props: cmdpkg.BoxProps) void {
    const box: *Box = @ptrCast(@alignCast(elem.userdata orelse return));

    if (props.opacity) |o| box.opacity = o;
    if (props.text_align) |ta| box.text_align = @enumFromInt(@intFromEnum(ta));
    if (props.rounded) |r| box.rounded = r;
}

fn applyStylePatch(elem: *Element, patch: cmdpkg.StylePatch) void {
    const node = elem.node;

    if (patch.direction) |v| {
        elem.style.direction = v;
        node.setDirection(v);
    }
    if (patch.flex_direction) |v| {
        elem.style.flex_direction = v;
        node.setFlexDirection(v);
    }
    if (patch.justify_content) |v| {
        elem.style.justify_content = v;
        node.setJustifyContent(v);
    }
    if (patch.align_content) |v| {
        elem.style.align_content = v;
        node.setAlignContent(v);
    }
    if (patch.align_items) |v| {
        elem.style.align_items = v;
        node.setAlignItems(v);
    }
    if (patch.align_self) |v| {
        elem.style.align_self = v;
        node.setAlignSelf(v);
    }
    if (patch.position_type) |v| {
        elem.style.position_type = v;
        node.setPositionType(v);
    }
    if (patch.flex_wrap) |v| {
        elem.style.flex_wrap = v;
        node.setFlexWrap(v);
    }
    if (patch.overflow) |v| {
        elem.style.overflow = v;
        node.setOverflow(v);
    }
    if (patch.display) |v| {
        elem.style.display = v;
        node.setDisplay(v);
    }
    if (patch.box_sizing) |v| {
        elem.style.box_sizing = v;
        node.setBoxSizing(v);
    }

    if (patch.flex) |v| {
        elem.style.flex = v;
        node.setFlex(v);
    }
    if (patch.flex_grow) |v| {
        elem.style.flex_grow = v;
        node.setFlexGrow(v);
    }
    if (patch.flex_shrink) |v| {
        elem.style.flex_shrink = v;
        node.setFlexShrink(v);
    }
    if (patch.flex_basis) |v| {
        elem.style.flex_basis = v;
        node.setFlexBasis(v);
    }

    if (patch.width) |v| {
        elem.style.width = v;
        node.setWidth(v);
    }
    if (patch.height) |v| {
        elem.style.height = v;
        node.setHeight(v);
    }
    if (patch.min_width) |v| {
        elem.style.min_width = v;
        node.setMinWidth(v);
    }
    if (patch.min_height) |v| {
        elem.style.min_height = v;
        node.setMinHeight(v);
    }
    if (patch.max_width) |v| {
        elem.style.max_width = v;
        node.setMaxWidth(v);
    }
    if (patch.max_height) |v| {
        elem.style.max_height = v;
        node.setMaxHeight(v);
    }

    if (patch.aspect_ratio) |v| {
        elem.style.aspect_ratio = v;
        node.setAspectRatio(v);
    }

    if (patch.position) |edges| applyEdgePatch(&elem.style.position, node, Node.setPosition, edges);
    if (patch.margin) |edges| applyEdgePatch(&elem.style.margin, node, Node.setMargin, edges);
    if (patch.padding) |edges| applyEdgePatch(&elem.style.padding, node, Node.setPadding, edges);
    if (patch.border) |edges| applyBorderEdgePatch(&elem.style.border, node, edges);
    if (patch.gap) |gap| applyGapPatch(&elem.style.gap, node, gap);
}

fn applyEdgePatch(edges: *Style.Edges, node: Node, setter: *const fn (Node, Style.Edge, Style.StyleValue) void, patch: cmdpkg.EdgeValues) void {
    const entries = .{
        .{ .edge = Style.Edge.left, .field = &edges.left, .val = patch.left },
        .{ .edge = Style.Edge.top, .field = &edges.top, .val = patch.top },
        .{ .edge = Style.Edge.right, .field = &edges.right, .val = patch.right },
        .{ .edge = Style.Edge.bottom, .field = &edges.bottom, .val = patch.bottom },
        .{ .edge = Style.Edge.start, .field = &edges.start, .val = patch.start },
        .{ .edge = Style.Edge.end, .field = &edges.end, .val = patch.end },
        .{ .edge = Style.Edge.horizontal, .field = &edges.horizontal, .val = patch.horizontal },
        .{ .edge = Style.Edge.vertical, .field = &edges.vertical, .val = patch.vertical },
        .{ .edge = Style.Edge.all, .field = &edges.all, .val = patch.all },
    };

    inline for (entries) |entry| {
        if (entry.val) |sv| {
            entry.field.* = sv;
            setter(node, entry.edge, sv);
        }
    }
}

fn applyBorderEdgePatch(border: *Style.BorderEdges, node: Node, patch: cmdpkg.BorderEdgeValues) void {
    const entries = .{
        .{ .edge = Style.Edge.left, .field = &border.left, .val = patch.left },
        .{ .edge = Style.Edge.top, .field = &border.top, .val = patch.top },
        .{ .edge = Style.Edge.right, .field = &border.right, .val = patch.right },
        .{ .edge = Style.Edge.bottom, .field = &border.bottom, .val = patch.bottom },
        .{ .edge = Style.Edge.start, .field = &border.start, .val = patch.start },
        .{ .edge = Style.Edge.end, .field = &border.end, .val = patch.end },
        .{ .edge = Style.Edge.horizontal, .field = &border.horizontal, .val = patch.horizontal },
        .{ .edge = Style.Edge.vertical, .field = &border.vertical, .val = patch.vertical },
        .{ .edge = Style.Edge.all, .field = &border.all, .val = patch.all },
    };

    inline for (entries) |entry| {
        if (entry.val) |f| {
            entry.field.* = f;
            node.setBorder(entry.edge, f);
        }
    }
}

fn applyGapPatch(gap: *Style.Gap, node: Node, patch: cmdpkg.GapValues) void {
    const entries = .{
        .{ .gutter = Style.Gutter.column, .field = &gap.column, .val = patch.column },
        .{ .gutter = Style.Gutter.row, .field = &gap.row, .val = patch.row },
        .{ .gutter = Style.Gutter.all, .field = &gap.all, .val = patch.all },
    };

    inline for (entries) |entry| {
        if (entry.val) |sv| {
            entry.field.* = sv;
            node.setGap(entry.gutter, sv);
        }
    }
}

const testing = std.testing;
const vaxis = @import("vaxis");

fn testSetup(alloc: Allocator) !struct { screen: *Screen, window: *Window, mutations: Mutations } {
    const screen = try alloc.create(Screen);
    screen.* = try Screen.init(alloc, .{ .cols = 80, .rows = 24, .x_pixel = 0, .y_pixel = 0 });

    const window = try alloc.create(Window);
    window.* = try Window.init(alloc, screen);

    return .{
        .screen = screen,
        .window = window,
        .mutations = .{ .alloc = alloc, .window = window },
    };
}

fn testTeardown(alloc: Allocator, ctx: *@TypeOf(testSetup(undefined) catch unreachable)) void {
    ctx.window.deinit();
    alloc.destroy(ctx.window);
    ctx.screen.deinit();
    alloc.destroy(ctx.screen);
}

const Screen = @import("../Screen.zig");

test "create element and set_root" {
    const alloc = testing.allocator;
    var ctx = try testSetup(alloc);
    defer testTeardown(alloc, &ctx);

    ctx.mutations.processMutations(
        \\[
        \\  {"cmd": 0, "id": 1, "element_type": 0},
        \\  {"cmd": 6, "id": 1}
        \\]
    );

    try testing.expect(ctx.window.getElement(1) != null);
    try testing.expect(ctx.window.root != null);
    try testing.expectEqual(@as(u64, 1), ctx.window.root.?.num);
}

test "set_props applies style" {
    const alloc = testing.allocator;
    var ctx = try testSetup(alloc);
    defer testTeardown(alloc, &ctx);

    ctx.mutations.processMutations(
        \\[
        \\  {"cmd": 0, "id": 1, "element_type": 0},
        \\  {"cmd": 1, "id": 1, "props": {"style": {
        \\    "flex_direction": "row",
        \\    "width": 100,
        \\    "height": 50
        \\  }}}
        \\]
    );

    const elem = ctx.window.getElement(1).?;
    try testing.expectEqual(Style.FlexDirection.row, elem.style.flex_direction);
    try testing.expectEqual(Style.StyleValue{ .point = 100.0 }, elem.style.width);
    try testing.expectEqual(Style.StyleValue{ .point = 50.0 }, elem.style.height);
}

test "set_props applies z_index and box props" {
    const alloc = testing.allocator;
    var ctx = try testSetup(alloc);
    defer testTeardown(alloc, &ctx);

    ctx.mutations.processMutations(
        \\[
        \\  {"cmd": 0, "id": 1, "element_type": 0},
        \\  {"cmd": 1, "id": 1, "props": {"zIndex": 5, "opacity": 0.5, "rounded": 4.0}}
        \\]
    );

    const elem = ctx.window.getElement(1).?;
    try testing.expectEqual(@as(usize, 5), elem.zIndex);

    const box: *Box = @ptrCast(@alignCast(elem.userdata.?));
    try testing.expectApproxEqAbs(@as(f32, 0.5), box.opacity, 0.001);
    try testing.expectApproxEqAbs(@as(f32, 4.0), box.rounded.?, 0.001);
}

test "append_child builds parent-child relationship" {
    const alloc = testing.allocator;
    var ctx = try testSetup(alloc);
    defer testTeardown(alloc, &ctx);

    ctx.mutations.processMutations(
        \\[
        \\  {"cmd": 0, "id": 1, "element_type": 0},
        \\  {"cmd": 0, "id": 2, "element_type": 0},
        \\  {"cmd": 2, "id": 1, "child_id": 2}
        \\]
    );

    const parent = ctx.window.getElement(1).?;
    const child = ctx.window.getElement(2).?;

    try testing.expect(parent.childrens != null);
    try testing.expectEqual(@as(usize, 1), parent.childrens.?.by_order.items.len);
    try testing.expect(child.parent == parent);
}

test "insert_before places child at correct position" {
    const alloc = testing.allocator;
    var ctx = try testSetup(alloc);
    defer testTeardown(alloc, &ctx);

    ctx.mutations.processMutations(
        \\[
        \\  {"cmd": 0, "id": 1, "element_type": 0},
        \\  {"cmd": 0, "id": 2, "element_type": 0},
        \\  {"cmd": 0, "id": 3, "element_type": 0},
        \\  {"cmd": 2, "id": 1, "child_id": 2},
        \\  {"cmd": 3, "id": 1, "child_id": 3, "before_id": 2}
        \\]
    );

    const parent = ctx.window.getElement(1).?;
    const children = parent.childrens.?.by_order.items;

    try testing.expectEqual(@as(usize, 2), children.len);
    try testing.expectEqual(@as(u64, 3), children[0].num);
    try testing.expectEqual(@as(u64, 2), children[1].num);
}

test "remove_child detaches child from parent" {
    const alloc = testing.allocator;
    var ctx = try testSetup(alloc);
    defer testTeardown(alloc, &ctx);

    ctx.mutations.processMutations(
        \\[
        \\  {"cmd": 0, "id": 1, "element_type": 0},
        \\  {"cmd": 0, "id": 2, "element_type": 0},
        \\  {"cmd": 2, "id": 1, "child_id": 2},
        \\  {"cmd": 4, "id": 1, "child_id": 2}
        \\]
    );

    const parent = ctx.window.getElement(1).?;
    try testing.expectEqual(@as(usize, 0), parent.childrens.?.by_order.items.len);

    const child = ctx.window.getElement(2).?;
    try testing.expect(child.parent == null);
}

test "delete removes element from window" {
    const alloc = testing.allocator;
    var ctx = try testSetup(alloc);
    defer testTeardown(alloc, &ctx);

    ctx.mutations.processMutations(
        \\[
        \\  {"cmd": 0, "id": 1, "element_type": 0},
        \\  {"cmd": 0, "id": 2, "element_type": 0},
        \\  {"cmd": 2, "id": 1, "child_id": 2},
        \\  {"cmd": 5, "id": 2}
        \\]
    );

    try testing.expect(ctx.window.getElement(2) == null);

    const parent = ctx.window.getElement(1).?;
    try testing.expectEqual(@as(usize, 0), parent.childrens.?.by_order.items.len);
}

test "set_focus updates focused_id" {
    const alloc = testing.allocator;
    var ctx = try testSetup(alloc);
    defer testTeardown(alloc, &ctx);

    ctx.mutations.processMutations(
        \\[
        \\  {"cmd": 0, "id": 1, "element_type": 0},
        \\  {"cmd": 7, "id": 1}
        \\]
    );

    try testing.expectEqual(@as(?u64, 1), ctx.window.focused_id);
}

test "set_props applies edge padding and margin" {
    const alloc = testing.allocator;
    var ctx = try testSetup(alloc);
    defer testTeardown(alloc, &ctx);

    ctx.mutations.processMutations(
        \\[
        \\  {"cmd": 0, "id": 1, "element_type": 0},
        \\  {"cmd": 1, "id": 1, "props": {"style": {
        \\    "padding": {"left": 5, "top": 10},
        \\    "margin": {"all": 2}
        \\  }}}
        \\]
    );

    const elem = ctx.window.getElement(1).?;
    try testing.expectEqual(Style.StyleValue{ .point = 5.0 }, elem.style.padding.left);
    try testing.expectEqual(Style.StyleValue{ .point = 10.0 }, elem.style.padding.top);
    try testing.expectEqual(Style.StyleValue{ .point = 2.0 }, elem.style.margin.all);
}

test "full tree: create, nest, set_root, then delete leaf" {
    const alloc = testing.allocator;
    var ctx = try testSetup(alloc);
    defer testTeardown(alloc, &ctx);

    ctx.mutations.processMutations(
        \\[
        \\  {"cmd": 0, "id": 10, "element_type": 0},
        \\  {"cmd": 0, "id": 20, "element_type": 0},
        \\  {"cmd": 0, "id": 30, "element_type": 0},
        \\  {"cmd": 2, "id": 10, "child_id": 20},
        \\  {"cmd": 2, "id": 10, "child_id": 30},
        \\  {"cmd": 6, "id": 10},
        \\  {"cmd": 1, "id": 20, "props": {"style": {"width": 40}}},
        \\  {"cmd": 5, "id": 30}
        \\]
    );

    try testing.expectEqual(@as(u64, 10), ctx.window.root.?.num);

    const root = ctx.window.getElement(10).?;
    try testing.expectEqual(@as(usize, 1), root.childrens.?.by_order.items.len);

    const child = ctx.window.getElement(20).?;
    try testing.expectEqual(Style.StyleValue{ .point = 40.0 }, child.style.width);

    try testing.expect(ctx.window.getElement(30) == null);
}
