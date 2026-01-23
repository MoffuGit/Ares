const std = @import("std");
const vaxis = @import("vaxis");
const yoga = @import("element/Node.zig").yoga;

const Element = @import("element/mod.zig").Element;
const Buffer = @import("Buffer.zig");
const AppContext = @import("AppContext.zig");
const Screen = @import("Screen.zig");
const HitGrid = @import("HitGrid.zig");
const events = @import("events/mod.zig");
const EventContext = events.EventContext;
const Event = events.Event;

pub const Elements = std.AutoHashMap(u64, *Element);
const Allocator = std.mem.Allocator;

const Window = @This();

const Options = struct {
    app_context: *AppContext,
    root_opts: Element.Options = .{},
};

alloc: Allocator,

needs_draw: std.atomic.Value(bool) = std.atomic.Value(bool).init(true),

root: *Element,

size: vaxis.Winsize,
screen: *Screen,

focused: ?*Element = null,
focus_path: std.ArrayList(*Element) = .{},
hit_grid: HitGrid = .{},
hovered: ?*Element = null,
pressed_on: ?*Element = null,
elements: Elements,

pub fn init(alloc: Allocator, screen: *Screen, opts: Options) !Window {
    const root = try alloc.create(Element);
    errdefer alloc.destroy(root);

    var root_opts = opts.root_opts;
    root_opts.id = "__root__";

    root.* = Element.init(alloc, root_opts);
    root.context = opts.app_context;

    var elements = Elements.init(alloc);
    try elements.put(root.num, root);

    return .{
        .screen = screen,
        .alloc = alloc,
        .root = root,
        .size = .{ .cols = 0, .rows = 0, .x_pixel = 0, .y_pixel = 0 },
        .elements = elements,
    };
}

pub fn deinit(self: *Window) void {
    self.root.remove();
    self.alloc.destroy(self.root);
    self.focus_path.deinit(self.alloc);
    self.hit_grid.deinit(self.alloc);
    self.elements.deinit();
}

pub fn addElement(self: *Window, elem: *Element) !void {
    try self.elements.put(elem.num, elem);
}

pub fn removeElement(self: *Window, num: u64) void {
    _ = self.elements.remove(num);
}

pub fn getElement(self: *Window, num: u64) ?*Element {
    return self.elements.get(num);
}

pub fn resize(self: *Window, size: vaxis.Winsize) void {
    if (self.size.rows == size.rows and self.size.cols == size.cols) return;

    self.size = size;
    self.requestDraw();
}

pub fn needsDraw(self: *Window) bool {
    return self.needs_draw.load(.acquire);
}

pub fn markDrawn(self: *Window) void {
    self.needs_draw.store(false, .release);
}

pub fn requestDraw(self: *Window) void {
    self.needs_draw.store(true, .release);
}

pub fn draw(self: *Window) !void {
    self.calculateLayout();

    const screen = self.screen;
    const size = self.size;

    if (self.hit_grid.width != size.cols or self.hit_grid.height != size.rows) {
        try self.hit_grid.resize(self.alloc, size.cols, size.rows);
    }

    const hit_grid = &self.hit_grid;

    hit_grid.fillRect(0, 0, hit_grid.width, hit_grid.height, self.root.num);
    self.root.hit(&self.hit_grid);

    const buffer = try screen.nextBuffer();
    errdefer screen.releaseBuffer();

    if (buffer.width != size.cols or buffer.height != size.rows) {
        try screen.resizeBuffer(self.alloc, buffer, size);
    }

    buffer.clear();

    self.root.draw(buffer);
}

pub fn calculateLayout(self: *Window) void {
    const root_node = self.root.node.yg_node;
    yoga.YGNodeCalculateLayout(root_node, @floatFromInt(self.size.cols), @floatFromInt(self.size.rows), yoga.YGDirectionLTR);
    applyLayout(self.root);
}

fn applyLayout(element: *Element) void {
    const node = element.node.yg_node;

    if (!yoga.YGNodeGetHasNewLayout(node)) {
        return;
    }

    yoga.YGNodeSetHasNewLayout(node, false);

    element.syncLayout();

    if (element.childrens) |*childrens| {
        for (childrens.by_order.items) |child| {
            applyLayout(child);
        }
    }
}

pub fn tryHit(self: *Window, col: u16, row: u16) ?*Element {
    const num = self.hit_grid.get(col, row) orelse return null;
    return self.getElement(num);
}

pub fn handleEvent(self: *Window, event: Event) !void {
    switch (event) {
        .mouse => |mouse| return self.handleMouseEvent(mouse),
        else => {},
    }

    var ctx = EventContext{
        .phase = .capturing,
        .target = self.focused,
    };

    switch (event) {
        .key_press => |key| self.handleKeyPress(&ctx, key),
        .key_release => |key| self.handleKeyRelease(&ctx, key),
        .blur => self.handleBlur(),
        .focus => self.handleFocus(),
        .mouse => unreachable,
    }

    if (ctx.stopped) return;

    const target = self.focused orelse return;

    ctx.phase = .capturing;
    for (self.focus_path.items) |element| {
        if (element == target) continue;
        element.handleEvent(&ctx, event);
        if (ctx.stopped) return;
    }

    ctx.phase = .at_target;

    target.handleEvent(&ctx, event);

    if (ctx.stopped) return;

    ctx.phase = .bubbling;
    var i: usize = self.focus_path.items.len;
    while (i > 0) {
        i -= 1;
        const element = self.focus_path.items[i];
        if (element == target) continue;
        element.handleEvent(&ctx, event);
        if (ctx.stopped) return;
    }
}

fn handleMouseEvent(self: *Window, mouse: vaxis.Mouse) void {
    const col: u16 = if (mouse.col < 0) 0 else @intCast(mouse.col);
    const row: u16 = if (mouse.row < 0) 0 else @intCast(mouse.row);

    const current_target = self.tryHit(col, row);
    const prev_hovered = self.hovered;

    self.processHoverChange(prev_hovered, current_target, mouse);

    switch (mouse.type) {
        .press => self.processMouseDown(current_target, mouse),
        .release => self.processMouseUp(current_target, mouse),
        .motion => self.processMouseMove(current_target, mouse),
        .drag => {},
    }

    self.processWheel(current_target, mouse);

    self.hovered = current_target;
}

fn processHoverChange(_: *Window, prev: ?*Element, current: ?*Element, mouse: vaxis.Mouse) void {
    if (prev == current) return;

    if (prev) |prev_elem| {
        const is_leaving = current == null or !prev_elem.isAncestorOf(current.?);
        if (is_leaving) {
            prev_elem.handleMouseLeave(mouse);
        }
        _ = dispatchMouseEvent(prev, mouse, Element.handleMouseOut);
    }

    if (current) |curr_elem| {
        const is_entering = prev == null or !curr_elem.isAncestorOf(prev.?);
        if (is_entering) {
            curr_elem.handleMouseEnter(mouse);
        }
        _ = dispatchMouseEvent(current, mouse, Element.handleMouseOver);
    }
}

const MouseHandler = *const fn (*Element, *EventContext, vaxis.Mouse) void;

fn dispatchMouseEvent(target: ?*Element, mouse: vaxis.Mouse, handler: MouseHandler) EventContext {
    var ctx = EventContext{ .phase = .at_target, .target = target };
    if (target) |elem| {
        handler(elem, &ctx, mouse);
        if (!ctx.stopped) {
            ctx.phase = .bubbling;
            bubble(elem.parent, &ctx, mouse, handler);
        }
    }
    return ctx;
}

fn bubble(start: ?*Element, ctx: *EventContext, mouse: vaxis.Mouse, handler: MouseHandler) void {
    var current = start;
    while (current) |elem| : (current = elem.parent) {
        handler(elem, ctx, mouse);
        if (ctx.stopped) return;
    }
}

fn processMouseDown(self: *Window, target: ?*Element, mouse: vaxis.Mouse) void {
    self.pressed_on = target;
    _ = dispatchMouseEvent(target, mouse, Element.handleMouseDown);
}

fn processMouseUp(self: *Window, target: ?*Element, mouse: vaxis.Mouse) void {
    const ctx = dispatchMouseEvent(target, mouse, Element.handleMouseUp);

    if (!ctx.stopped and self.pressed_on == target and target != null) {
        _ = dispatchMouseEvent(target, mouse, Element.handleClick);
    }
    self.pressed_on = null;
}

fn processMouseMove(_: *Window, target: ?*Element, mouse: vaxis.Mouse) void {
    _ = dispatchMouseEvent(target, mouse, Element.handleMouseMove);
}

fn processWheel(_: *Window, target: ?*Element, mouse: vaxis.Mouse) void {
    const is_wheel = switch (mouse.button) {
        .wheel_up, .wheel_down, .wheel_left, .wheel_right => true,
        else => false,
    };
    if (!is_wheel) return;

    _ = dispatchMouseEvent(target, mouse, Element.handleWheel);
}

pub fn handleKeyPress(self: *Window, ctx: *EventContext, key: vaxis.Key) void {
    self.root.handleKeyPress(ctx, key);
}

pub fn handleKeyRelease(self: *Window, ctx: *EventContext, key: vaxis.Key) void {
    self.root.handleKeyRelease(ctx, key);
}

pub fn handleFocus(self: *Window) void {
    self.root.handleFocus();
}

pub fn handleBlur(self: *Window) void {
    self.root.handleBlur();
}

pub fn setFocus(self: *Window, element: ?*Element) void {
    if (self.focused == element) return;

    const previous = self.focused;

    if (previous) |prev| {
        prev.handleBlur();
    }

    self.focused = element;
    self.rebuildFocusPath();

    if (element) |elem| {
        elem.handleFocus();
    }
}

fn rebuildFocusPath(self: *Window) void {
    self.focus_path.clearRetainingCapacity();

    var current: ?*Element = self.focused;
    while (current) |elem| : (current = elem.parent) {
        self.focus_path.append(self.alloc, elem) catch break;
    }

    std.mem.reverse(*Element, self.focus_path.items);
}

pub fn getFocus(self: *Window) ?*Element {
    return self.focused;
}
