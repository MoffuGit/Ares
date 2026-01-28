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
    root.removed = false;
    root.hitGridFn = HitGrid.hitElement;

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
    self.root.deinit();
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

    const hit_grid = &self.hit_grid;

    if (hit_grid.width != size.cols or hit_grid.height != size.rows) {
        try hit_grid.resize(self.alloc, size.cols, size.rows);
    }

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
    if (event == .mouse) {
        return self.handleMouseEvent(event.mouse);
    }

    var ctx = EventContext{
        .phase = .capturing,
        .target = self.focused,
    };

    const target = self.focused orelse self.root;

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
        .motion, .drag => self.processMouseMove(current_target, mouse),
    }

    const is_wheel = switch (mouse.button) {
        .wheel_up,
        .wheel_down,
        .wheel_left,
        .wheel_right,
        => true,
        else => false,
    };

    if (is_wheel) {
        self.processWheel(current_target, mouse);
    }

    self.hovered = current_target;
}

fn processHoverChange(_: *Window, prev: ?*Element, current: ?*Element, mouse: vaxis.Mouse) void {
    if (prev == current) return;

    if (prev) |prev_elem| {
        const is_leaving = current == null or !prev_elem.isAncestorOf(current.?);
        if (is_leaving) {
            prev_elem.emit(.{ .mouse_leave = mouse });
        }
        _ = dispatchMouseEvent(prev, .{ .mouse_out = .{ .ctx = undefined, .mouse = mouse } });
    }

    if (current) |curr_elem| {
        const is_entering = prev == null or !curr_elem.isAncestorOf(prev.?);
        if (is_entering) {
            curr_elem.emit(.{ .mouse_enter = mouse });
        }
        _ = dispatchMouseEvent(current, .{ .mouse_over = .{ .ctx = undefined, .mouse = mouse } });
    }
}

fn dispatchMouseEvent(target: ?*Element, data: Element.EventData) EventContext {
    var ctx = EventContext{ .phase = .at_target, .target = target };
    if (target) |elem| {
        const event_data = updateEventContext(data, &ctx);
        elem.emit(event_data);
        if (!ctx.stopped) {
            ctx.phase = .bubbling;
            bubble(elem.parent, &ctx, data);
        }
    }
    return ctx;
}

fn updateEventContext(data: Element.EventData, ctx: *EventContext) Element.EventData {
    return switch (data) {
        .mouse_down => |d| .{ .mouse_down = .{ .ctx = ctx, .mouse = d.mouse } },
        .mouse_up => |d| .{ .mouse_up = .{ .ctx = ctx, .mouse = d.mouse } },
        .click => |d| .{ .click = .{ .ctx = ctx, .mouse = d.mouse } },
        .mouse_move => |d| .{ .mouse_move = .{ .ctx = ctx, .mouse = d.mouse } },
        .mouse_over => |d| .{ .mouse_over = .{ .ctx = ctx, .mouse = d.mouse } },
        .mouse_out => |d| .{ .mouse_out = .{ .ctx = ctx, .mouse = d.mouse } },
        .wheel => |d| .{ .wheel = .{ .ctx = ctx, .mouse = d.mouse } },
        .drag => |d| .{ .drag = .{ .ctx = ctx, .mouse = d.mouse } },
        .drag_end => |d| .{ .drag_end = .{ .ctx = ctx, .mouse = d.mouse } },
        else => data,
    };
}

fn bubble(start: ?*Element, ctx: *EventContext, data: Element.EventData) void {
    var current = start;
    while (current) |elem| : (current = elem.parent) {
        elem.emit(updateEventContext(data, ctx));
        if (ctx.stopped) return;
    }
}

fn processMouseDown(self: *Window, target: ?*Element, mouse: vaxis.Mouse) void {
    self.pressed_on = target;
    _ = dispatchMouseEvent(target, .{ .mouse_down = .{ .ctx = undefined, .mouse = mouse } });
}

fn processMouseUp(self: *Window, target: ?*Element, mouse: vaxis.Mouse) void {
    const ctx = dispatchMouseEvent(target, .{ .mouse_up = .{ .ctx = undefined, .mouse = mouse } });

    if (self.pressed_on) |pressed| {
        if (pressed.dragging) {
            _ = dispatchMouseEvent(pressed, .{ .drag_end = .{ .ctx = undefined, .mouse = mouse } });
        }
    }

    if (!ctx.stopped and self.pressed_on == target and target != null) {
        _ = dispatchMouseEvent(target, .{ .click = .{ .ctx = undefined, .mouse = mouse } });
    }
    self.pressed_on = null;
}

fn processMouseMove(self: *Window, target: ?*Element, mouse: vaxis.Mouse) void {
    _ = dispatchMouseEvent(target, .{ .mouse_move = .{ .ctx = undefined, .mouse = mouse } });
    if (mouse.type == .drag) {
        if (self.pressed_on) |pressed| {
            _ = dispatchMouseEvent(pressed, .{ .drag = .{ .ctx = undefined, .mouse = mouse } });
        }
    }
}

fn processWheel(_: *Window, target: ?*Element, mouse: vaxis.Mouse) void {
    _ = dispatchMouseEvent(target, .{ .wheel = .{ .ctx = undefined, .mouse = mouse } });
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

    self.requestDraw();
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

const testing = std.testing;

fn initTestWindow(alloc: Allocator) !struct { window: Window, screen: *Screen } {
    const screen = try alloc.create(Screen);
    screen.* = try Screen.init(alloc, .{ .cols = 80, .rows = 24, .x_pixel = 0, .y_pixel = 0 });

    var window = try Window.init(alloc, screen, .{ .app_context = undefined });
    window.root.context = null;

    return .{ .window = window, .screen = screen };
}

fn deinitTestWindow(alloc: Allocator, window: *Window, screen: *Screen) void {
    window.deinit();
    screen.deinit(alloc);
    alloc.destroy(screen);
}

test "addChild registers element in window map" {
    const alloc = testing.allocator;
    var state = try initTestWindow(alloc);
    defer deinitTestWindow(alloc, &state.window, state.screen);

    var child = Element.init(alloc, .{});
    defer child.deinit();

    var app_context = AppContext{
        .userdata = null,
        .mailbox = undefined,
        .wakeup = undefined,
        .stop = undefined,
        .needs_draw = undefined,
        .window = &state.window,
    };
    state.window.root.context = &app_context;

    try state.window.root.addChild(&child);

    try testing.expect(state.window.elements.count() == 2);
    try testing.expect(state.window.getElement(child.num) == &child);
}

test "removeChild removes element from window map" {
    const alloc = testing.allocator;
    var state = try initTestWindow(alloc);
    defer deinitTestWindow(alloc, &state.window, state.screen);

    var child = Element.init(alloc, .{});
    defer child.deinit();

    var app_context = AppContext{
        .userdata = null,
        .mailbox = undefined,
        .wakeup = undefined,
        .stop = undefined,
        .needs_draw = undefined,
        .window = &state.window,
    };
    state.window.root.context = &app_context;

    try state.window.root.addChild(&child);
    try testing.expect(state.window.elements.count() == 2);

    state.window.root.removeChild(child.num);

    try testing.expect(state.window.elements.count() == 1);
    try testing.expect(state.window.getElement(child.num) == null);
}

test "nested children all registered in window map" {
    const alloc = testing.allocator;
    var state = try initTestWindow(alloc);
    defer deinitTestWindow(alloc, &state.window, state.screen);

    var child1 = Element.init(alloc, .{});
    defer child1.deinit();

    var child2 = Element.init(alloc, .{});
    defer child2.deinit();

    var app_context = AppContext{
        .userdata = null,
        .mailbox = undefined,
        .wakeup = undefined,
        .stop = undefined,
        .needs_draw = undefined,
        .window = &state.window,
    };
    state.window.root.context = &app_context;

    try child1.addChild(&child2);
    try state.window.root.addChild(&child1);

    try testing.expect(state.window.elements.count() == 3);
    try testing.expect(state.window.getElement(child1.num) == &child1);
    try testing.expect(state.window.getElement(child2.num) == &child2);
}

test "element remove function" {
    const alloc = testing.allocator;
    var state = try initTestWindow(alloc);
    defer deinitTestWindow(alloc, &state.window, state.screen);

    var child = Element.init(alloc, .{});
    defer child.deinit();

    var app_context = AppContext{
        .userdata = null,
        .mailbox = undefined,
        .wakeup = undefined,
        .stop = undefined,
        .needs_draw = undefined,
        .window = &state.window,
    };
    state.window.root.context = &app_context;

    try state.window.root.addChild(&child);
    try testing.expect(state.window.elements.count() == 2);
    try testing.expect(state.window.getElement(child.num) == &child);

    child.remove();

    try testing.expect(state.window.elements.count() == 1);
    try testing.expect(state.window.getElement(child.num) == null);
    try testing.expect(child.removed == true);
    try testing.expect(child.parent == null);
    try testing.expect(child.context == null);
}

test "element remove() removes nested children" {
    const alloc = testing.allocator;
    var state = try initTestWindow(alloc);
    defer deinitTestWindow(alloc, &state.window, state.screen);

    var child1 = Element.init(alloc, .{});
    defer child1.deinit();

    var child2 = Element.init(alloc, .{});
    defer child2.deinit();

    var app_context = AppContext{
        .userdata = null,
        .mailbox = undefined,
        .wakeup = undefined,
        .stop = undefined,
        .needs_draw = undefined,
        .window = &state.window,
    };
    state.window.root.context = &app_context;

    try state.window.root.addChild(&child1);
    try child1.addChild(&child2);
    try testing.expect(state.window.elements.count() == 3);

    child1.remove();

    try testing.expect(state.window.elements.count() == 1);
    try testing.expect(state.window.getElement(child1.num) == null);
    try testing.expect(state.window.getElement(child2.num) == null);
    try testing.expect(child1.removed == true);
    try testing.expect(child2.removed == true);
}

test "element remove() happens once" {
    const alloc = testing.allocator;
    var state = try initTestWindow(alloc);
    defer deinitTestWindow(alloc, &state.window, state.screen);

    var child = Element.init(alloc, .{});
    defer child.deinit();

    var app_context = AppContext{
        .userdata = null,
        .mailbox = undefined,
        .wakeup = undefined,
        .stop = undefined,
        .needs_draw = undefined,
        .window = &state.window,
    };
    state.window.root.context = &app_context;

    try state.window.root.addChild(&child);

    child.remove();
    try testing.expect(state.window.elements.count() == 1);

    child.remove();
    try testing.expect(state.window.elements.count() == 1);
}
