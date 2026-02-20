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
    if (self.hovered) |h| {
        if (h.num == num) self.hovered = null;
    }
    if (self.pressed_on) |p| {
        if (p.num == num) self.pressed_on = null;
    }
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
    applyLayout(self.root, false);
}

fn applyLayout(element: *Element, parent_changed: bool) void {
    const node = element.node.yg_node;

    const new_layout = yoga.YGNodeGetHasNewLayout(node);

    if (!new_layout and !parent_changed) {
        return;
    }

    if (new_layout) {
        yoga.YGNodeSetHasNewLayout(node, false);
    }

    const position = element.syncLayout();

    if (element.childrens) |*childrens| {
        for (childrens.by_order.items) |child| {
            applyLayout(child, new_layout or position);
        }
    }
}

pub fn tryHit(self: *Window, col: u16, row: u16) ?*Element {
    const num = self.hit_grid.get(col, row) orelse return null;
    return self.getElement(num);
}

pub fn dispatchEvent(target: *Element, ctx: *EventContext, data: Element.ElementEvent) void {
    var event = data;

    ctx.* = .{ .phase = .capturing, .target = target };
    capture(target, ctx, &event);

    if (ctx.stopped) return;

    ctx.phase = .at_target;
    event.element = target;
    target.dispatchEvent(event);

    if (ctx.stopped) return;

    ctx.phase = .bubbling;
    bubble(target, ctx, &event);
}

fn capture(target: *Element, ctx: *EventContext, data: *Element.ElementEvent) void {
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
        data.element = path[i];
        path[i].dispatchEvent(data.*);
        if (ctx.stopped) return;
    }
}

fn bubble(target: *Element, ctx: *EventContext, data: *Element.ElementEvent) void {
    var current = target.parent;
    while (current) |elem| : (current = elem.parent) {
        data.element = elem;
        elem.dispatchEvent(data.*);
        if (ctx.stopped) return;
    }
}

pub fn handleEvent(self: *Window, event: Event) !void {
    if (event == .mouse) {
        const mouse = Mouse.fromVaxis(event.mouse, self.size);
        return self.handleMouseEvent(mouse);
    }

    const target = self.focused orelse self.root;

    var ctx = EventContext{
        .target = target,
    };

    const event_data = switch (event) {
        .blur => Element.ElementData{ .blur = {} },
        .focus => Element.ElementData{ .focus = {} },
        .key_press => |key| Element.ElementData{ .key_press = key },
        .key_release => |key| Element.ElementData{ .key_release = key },
        else => return,
    };

    dispatchEvent(target, &ctx, .{ .ctx = &ctx, .element = target, .event = event_data });
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

    if (prev_target) |prev| {
        var ctx = EventContext{ .target = prev };
        const is_leaving = curr_target == null or !prev.isAncestorOf(curr_target.?);
        prev.hovered = false;
        if (is_leaving) {
            dispatchEvent(prev, &ctx, .{ .ctx = &ctx, .element = prev, .event = .{ .mouse_leave = mouse } });
        }

        dispatchEvent(prev, &ctx, .{ .ctx = &ctx, .element = prev, .event = .{ .mouse_out = mouse } });
    }

    if (curr_target) |curr| {
        var ctx = EventContext{ .target = curr };
        const is_entering = prev_target == null or !curr.isAncestorOf(prev_target.?);
        curr.hovered = true;
        if (is_entering) {
            dispatchEvent(curr, &ctx, .{ .ctx = &ctx, .element = curr, .event = .{ .mouse_enter = mouse } });
        }
        dispatchEvent(curr, &ctx, .{ .ctx = &ctx, .element = curr, .event = .{ .mouse_over = mouse } });
    }

    self.hovered = curr_target;
}

fn processMouseDown(self: *Window, target: *Element, mouse: Mouse) void {
    self.pressed_on = target;
    var ctx = EventContext{ .target = target };
    dispatchEvent(target, &ctx, .{ .ctx = &ctx, .element = target, .event = .{ .mouse_down = mouse } });
}

fn processMouseUp(self: *Window, target: *Element, mouse: Mouse) void {
    var ctx = EventContext{ .target = target };
    dispatchEvent(target, &ctx, .{ .ctx = &ctx, .element = target, .event = .{ .mouse_up = mouse } });

    if (self.pressed_on) |pressed| {
        if (pressed.dragging) {
            pressed.dragging = false;
            dispatchEvent(pressed, &ctx, .{ .ctx = &ctx, .element = target, .event = .{ .drag_end = mouse } });
        }
    }

    if (!ctx.stopped and self.pressed_on == target) {
        dispatchEvent(target, &ctx, .{ .ctx = &ctx, .element = target, .event = .{ .click = mouse } });
    }
    self.pressed_on = null;
}

fn processMouseMove(self: *Window, target: *Element, mouse: Mouse) void {
    var ctx = EventContext{ .target = target };

    dispatchEvent(target, &ctx, .{ .ctx = &ctx, .element = target, .event = .{ .mouse_move = mouse } });
    if (mouse.type == .drag) {
        if (self.pressed_on) |pressed| {
            pressed.dragging = true;
            dispatchEvent(pressed, &ctx, .{ .ctx = &ctx, .element = target, .event = .{ .drag = mouse } });
        }
    }
}

fn processWheel(_: *Window, target: *Element, mouse: Mouse) void {
    var ctx = EventContext{ .target = target };
    dispatchEvent(target, &ctx, .{ .ctx = &ctx, .element = target, .event = .{ .wheel = mouse } });
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
