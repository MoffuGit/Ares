const std = @import("std");
const vaxis = @import("vaxis");
const yoga = @import("element/Node.zig").yoga;
const global = @import("../../global.zig");

pub const Element = @import("element/mod.zig");
const Buffer = @import("../Buffer.zig");
const apppkg = @import("../mod.zig");
const Context = apppkg.Context;
const Screen = @import("../Screen.zig");
const HitGrid = @import("HitGrid.zig");
const Allocator = std.mem.Allocator;
const Elements = std.AutoHashMap(u64, *Element);
const eventpkg = @import("event.zig");
const Event = eventpkg.Event;
const Mouse = eventpkg.Mouse;
const EventContext = @import("EventContext.zig");
const TimeManager = @import("TimeManager.zig");
const messagepkg = @import("message.zig");

pub const Message = messagepkg.Message;

const Window = @This();

const Options = struct {
    context: *Context,
    root: Element.Options = .{},
};

alloc: Allocator,
context: *Context,

root: *Element,

size: vaxis.Winsize,
screen: *Screen,
time: TimeManager,

focused: ?*Element = null,
focus_path: std.ArrayList(*Element) = .{},
hit_grid: HitGrid,
hovered: ?*Element = null,
pressed_on: ?*Element = null,
elements: Elements,

pub fn init(alloc: Allocator, screen: *Screen, opts: Options) !Window {
    const root = try alloc.create(Element);
    errdefer alloc.destroy(root);

    var root_opts = opts.root;
    root_opts.id = "__root__";

    root.* = Element.init(alloc, root_opts);
    root.context = opts.context;
    root.removed = false;
    root.hitFn = Element.hitSelf;

    var elements = Elements.init(alloc);
    try elements.put(root.num, root);

    const hit_grid = try HitGrid.init(alloc, 0, 0);

    const time = TimeManager.init(alloc);

    return .{
        .screen = screen,
        .time = time,
        .alloc = alloc,
        .context = opts.context,
        .root = root,
        .size = .{ .cols = 0, .rows = 0, .x_pixel = 0, .y_pixel = 0 },
        .elements = elements,
        .hit_grid = hit_grid,
    };
}

pub fn deinit(self: *Window) void {
    self.root.deinit();
    self.alloc.destroy(self.root);
    self.focus_path.deinit(self.alloc);
    self.hit_grid.deinit();
    self.elements.deinit();
    self.time.deinit();
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

pub fn requestDraw(self: *Window) void {
    self.context.requestDraw();
}

pub fn draw(self: *Window) !void {
    self.root.update();

    self.calculateLayout();

    const screen = self.screen;
    const size = self.size;

    const hit_grid = &self.hit_grid;

    if (hit_grid.width != size.cols or hit_grid.height != size.rows) {
        try hit_grid.resize(size.cols, size.rows);
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
    applyLayout(self.root, 0);
}

fn applyLayout(element: *Element, depth: u32) void {
    applyLayoutInner(element, depth, false);
}

//NOTE:
//if any element has their left or top value changed,
//we need to update their childrens top and left values as well,
//yoga put the responsability of calculating the top and left values
//to us, why?, i don't know
fn applyLayoutInner(element: *Element, depth: u32, parent_changed: bool) void {
    const node = element.node.yg_node;

    const new_layout = yoga.YGNodeGetHasNewLayout(node);

    if (!new_layout and !parent_changed) {
        return;
    }

    if (new_layout) {
        yoga.YGNodeSetHasNewLayout(node, false);
    }

    element.syncLayout();

    if (element.childrens) |*childrens| {
        for (childrens.by_order.items) |child| {
            applyLayoutInner(child, depth + 1, new_layout);
        }
    }
}

pub fn tryHit(self: *Window, col: u16, row: u16) ?*Element {
    const num = self.hit_grid.get(col, row) orelse return null;
    return self.getElement(num);
}

pub fn dispatchEvent(target: *Element, ctx: *EventContext, data: Element.EventData) void {
    ctx.* = .{ .phase = .capturing, .target = target };

    capture(target, ctx, data);

    if (ctx.stopped) return;

    ctx.phase = .at_target;
    target.dispatchEvent(data);

    if (ctx.stopped) return;

    ctx.phase = .bubbling;
    bubble(target, ctx, data);
}
fn capture(target: *Element, ctx: *EventContext, data: Element.EventData) void {
    var path: [64]*Element = undefined;
    var depth: usize = 0;

    var current: ?*Element = target.parent;
    while (current) |elem| : (current = elem.parent) {
        if (depth >= path.len) break;
        path[depth] = elem;
        depth += 1;
    }

    var i: usize = depth;
    while (i > 0) {
        i -= 1;
        path[i].dispatchEvent(data);
        if (ctx.stopped) return;
    }
}

fn bubble(target: *Element, ctx: *EventContext, data: Element.EventData) void {
    var current = target.parent;
    while (current) |elem| : (current = elem.parent) {
        elem.dispatchEvent(data);
        if (ctx.stopped) return;
    }
}

pub fn handleEvent(self: *Window, event: Event) !void {
    if (event == .mouse) {
        const mouse = Mouse.fromVaxis(event.mouse, self.size);
        return self.handleMouseEvent(mouse);
    }

    var ctx: EventContext = .{};

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

fn handleMouseEvent(self: *Window, mouse: Mouse) void {
    const curr = self.tryHit(mouse.col, mouse.row);
    const prev = self.hovered;

    self.processHoverChange(prev, curr, mouse);

    if (curr) |target| {
        switch (mouse.type) {
            .press => self.processMouseDown(target, mouse),
            .release => self.processMouseUp(target, mouse),
            .motion, .drag => self.processMouseMove(target, mouse),
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
            self.processWheel(target, mouse);
        }
    }
}

fn processHoverChange(self: *Window, prev_target: ?*Element, curr_target: ?*Element, mouse: Mouse) void {
    if (prev_target == curr_target) return;

    var ctx: EventContext = .{};

    if (prev_target) |prev| {
        const is_leaving = curr_target == null or !prev.isAncestorOf(curr_target.?);
        prev.hovered = false;
        if (is_leaving) {
            dispatchEvent(prev, &ctx, .{ .mouse_leave = .{ .element = prev, .mouse = mouse } });
        }

        dispatchEvent(prev, &ctx, .{ .mouse_out = .{ .element = prev, .ctx = &ctx, .mouse = mouse } });
    }

    if (curr_target) |curr| {
        const is_entering = prev_target == null or !curr.isAncestorOf(prev_target.?);
        curr.hovered = true;
        if (is_entering) {
            dispatchEvent(curr, &ctx, .{ .mouse_enter = .{ .element = curr, .mouse = mouse } });
        }
        dispatchEvent(curr, &ctx, .{ .mouse_over = .{ .element = curr, .ctx = &ctx, .mouse = mouse } });
    }

    self.hovered = curr_target;
}

fn processMouseDown(self: *Window, target: *Element, mouse: Mouse) void {
    self.pressed_on = target;
    var ctx: EventContext = .{};
    dispatchEvent(target, &ctx, .{ .mouse_down = .{ .element = target, .ctx = &ctx, .mouse = mouse } });
}

fn processMouseUp(self: *Window, target: *Element, mouse: Mouse) void {
    var ctx: EventContext = .{};
    dispatchEvent(target, &ctx, .{ .mouse_up = .{ .element = target, .ctx = &ctx, .mouse = mouse } });

    if (self.pressed_on) |pressed| {
        if (pressed.dragging) {
            pressed.dragging = false;
            dispatchEvent(pressed, &ctx, .{ .drag_end = .{ .element = pressed, .ctx = &ctx, .mouse = mouse } });
        }
    }

    if (!ctx.stopped and self.pressed_on == target) {
        dispatchEvent(target, &ctx, .{ .click = .{ .element = target, .ctx = &ctx, .mouse = mouse } });
    }
    self.pressed_on = null;
}

fn processMouseMove(self: *Window, target: *Element, mouse: Mouse) void {
    var ctx: EventContext = .{};

    dispatchEvent(target, &ctx, .{ .mouse_move = .{ .element = target, .ctx = &ctx, .mouse = mouse } });
    if (mouse.type == .drag) {
        if (self.pressed_on) |pressed| {
            pressed.dragging = true;
            dispatchEvent(pressed, &ctx, .{ .drag = .{ .element = pressed, .ctx = &ctx, .mouse = mouse } });
        }
    }
}

fn processWheel(_: *Window, target: *Element, mouse: Mouse) void {
    var ctx: EventContext = .{};
    dispatchEvent(target, &ctx, .{ .wheel = .{ .element = target, .ctx = &ctx, .mouse = mouse } });
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
        prev.focused = false;
        prev.handleBlur();
    }

    self.focused = element;
    self.rebuildFocusPath();

    if (element) |elem| {
        elem.focused = true;
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

pub fn handleMessage(self: *Window, msg: Message) !void {
    switch (msg) {
        .resize => |size| {
            self.resize(size);
        },
        .tick => |tick| {
            try self.time.addTick(tick);
        },
        .animation => |animation| {
            try self.time.handleAnimation(animation);
        },
        .timer => |timer| {
            try self.time.handleTimer(timer);
        },
        .event => |evt| {
            try self.handleEvent(evt);
        },
    }
}
