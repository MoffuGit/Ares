const std = @import("std");
const vaxis = @import("vaxis");

const Element = @import("element/Element.zig");
const Buffer = @import("Buffer.zig");
const AppContext = @import("AppContext.zig");
const Screen = @import("Screen.zig");
const HitGrid = @import("HitGrid.zig");
const events = @import("events/mod.zig");
const EventContext = events.EventContext;
const Event = events.Event;

pub const ElementMap = std.AutoHashMap(u64, *Element);
const Allocator = std.mem.Allocator;

const Window = @This();

const Options = struct {
    app_context: *AppContext,
    root_opts: Element.Opts = .{},
};

alloc: Allocator,

needs_draw: std.atomic.Value(bool) = std.atomic.Value(bool).init(true),

root: *Element,

size: vaxis.Winsize,
screen: *Screen,
app_context: *AppContext,

focused: ?*Element = null,
focus_path: std.ArrayListUnmanaged(*Element) = .{},
hit_grid: HitGrid = .{},
hovered: ?*Element = null,
pressed_on: ?*Element = null,
element_map: ElementMap,

pub fn init(alloc: Allocator, screen: *Screen, opts: Options) !Window {
    const root = try alloc.create(Element);
    errdefer alloc.destroy(root);

    var root_opts = opts.root_opts;
    root_opts.id = "__root__";
    if (root_opts.drawFn == null) root_opts.drawFn = drawRoot;
    if (root_opts.hitGridFn == null) root_opts.hitGridFn = hitGridRoot;

    root.* = Element.init(alloc, root_opts);

    return .{
        .app_context = opts.app_context,
        .screen = screen,
        .alloc = alloc,
        .root = root,
        .size = .{ .cols = 0, .rows = 0, .x_pixel = 0, .y_pixel = 0 },
        .element_map = ElementMap.init(alloc),
    };
}

pub fn deinit(self: *Window) void {
    self.root.remove();
    self.alloc.destroy(self.root);
    self.focus_path.deinit(self.alloc);
    self.hit_grid.deinit(self.alloc);
    self.element_map.deinit();
}

pub fn setContext(self: *Window, ctx: *AppContext) void {
    self.root.setContext(ctx);
}

pub fn registerElement(self: *Window, elem: *Element) void {
    self.element_map.put(elem.num, elem) catch {};
}

pub fn unregisterElement(self: *Window, elem: *Element) void {
    _ = self.element_map.remove(elem.num);
}

pub fn getElementByNum(self: *Window, num: u64) ?*Element {
    return self.element_map.get(num);
}

pub fn resize(self: *Window, size: vaxis.Winsize) void {
    if (self.size.rows == size.rows and self.size.cols == size.cols) return;

    self.size = size;
    self.needs_draw.store(true, .release);
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
    const screen = self.screen;
    const buffer = try screen.nextBuffer();
    errdefer screen.releaseBuffer();

    const size = self.size;
    if (buffer.width != size.cols or buffer.height != size.rows) {
        try screen.resizeBuffer(self.alloc, buffer, size);
        try self.hit_grid.resize(self.alloc, size.cols, size.rows);
    }

    try self.root.update();
    self.root.draw(buffer);

    self.hit_grid.clear();
    self.root.hit(&self.hit_grid);
}

fn drawRoot(_: *Element, buffer: *Buffer) void {
    const cell: vaxis.Cell = .{ .style = .{ .bg = .{ .rgb = .{ 255, 0, 0 } } } };
    buffer.fill(cell);
}

fn hitGridRoot(element: *Element, hit_grid: *HitGrid) void {
    hit_grid.fillRect(0, 0, hit_grid.width, hit_grid.height, element.num);
}

pub fn getElementAt(self: *Window, col: u16, row: u16) ?*Element {
    const num = self.hit_grid.get(col, row) orelse return null;
    return self.getElementByNum(num);
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

    const current_target = self.getElementAt(col, row);
    const prev_hovered = self.hovered;

    self.processHoverChange(prev_hovered, current_target, mouse);

    switch (mouse.type) {
        .press => self.processMouseDown(current_target, mouse),
        .release => self.processMouseUp(current_target, mouse),
        .motion, .drag => self.processMouseMove(current_target, mouse),
    }

    self.processWheel(current_target, mouse);

    self.hovered = current_target;
}

fn processHoverChange(self: *Window, prev: ?*Element, current: ?*Element, mouse: vaxis.Mouse) void {
    if (prev == current) return;

    var out_ctx = EventContext{ .phase = .at_target, .target = prev };
    var over_ctx = EventContext{ .phase = .at_target, .target = current };

    if (prev) |prev_elem| {
        const is_leaving = current == null or !prev_elem.isAncestorOf(current.?);
        if (is_leaving) {
            prev_elem.handleMouseLeave(mouse);
        }

        out_ctx.phase = .at_target;
        prev_elem.handleMouseOut(&out_ctx, mouse);
        if (!out_ctx.stopped) {
            out_ctx.phase = .bubbling;
            self.bubbleMouseOut(prev_elem.parent, &out_ctx, mouse);
        }
    }

    if (current) |curr_elem| {
        const is_entering = prev == null or !curr_elem.isAncestorOf(prev.?);
        if (is_entering) {
            curr_elem.handleMouseEnter(mouse);
        }

        over_ctx.phase = .at_target;
        curr_elem.handleMouseOver(&over_ctx, mouse);
        if (!over_ctx.stopped) {
            over_ctx.phase = .bubbling;
            self.bubbleMouseOver(curr_elem.parent, &over_ctx, mouse);
        }
    }
}

fn processMouseDown(self: *Window, target: ?*Element, mouse: vaxis.Mouse) void {
    self.pressed_on = target;

    var ctx = EventContext{ .phase = .at_target, .target = target };

    if (target) |elem| {
        elem.handleMouseDown(&ctx, mouse);
        if (!ctx.stopped) {
            ctx.phase = .bubbling;
            self.bubbleMouseDown(elem.parent, &ctx, mouse);
        }
    }
}

fn processMouseUp(self: *Window, target: ?*Element, mouse: vaxis.Mouse) void {
    var ctx = EventContext{ .phase = .at_target, .target = target };

    if (target) |elem| {
        elem.handleMouseUp(&ctx, mouse);
        if (!ctx.stopped) {
            ctx.phase = .bubbling;
            self.bubbleMouseUp(elem.parent, &ctx, mouse);
        }
    }

    if (!ctx.stopped and self.pressed_on == target and target != null) {
        self.processClick(target.?, mouse);
    }
    self.pressed_on = null;
}

fn processClick(self: *Window, target: *Element, mouse: vaxis.Mouse) void {
    var ctx = EventContext{ .phase = .at_target, .target = target };

    target.handleClick(&ctx, mouse);
    if (!ctx.stopped) {
        ctx.phase = .bubbling;
        self.bubbleClick(target.parent, &ctx, mouse);
    }
}

fn processMouseMove(self: *Window, target: ?*Element, mouse: vaxis.Mouse) void {
    var ctx = EventContext{ .phase = .at_target, .target = target };

    if (target) |elem| {
        elem.handleMouseMove(&ctx, mouse);
        if (!ctx.stopped) {
            ctx.phase = .bubbling;
            self.bubbleMouseMove(elem.parent, &ctx, mouse);
        }
    }
}

fn processWheel(self: *Window, target: ?*Element, mouse: vaxis.Mouse) void {
    const is_wheel = switch (mouse.button) {
        .wheel_up, .wheel_down, .wheel_left, .wheel_right => true,
        else => false,
    };
    if (!is_wheel) return;

    var ctx = EventContext{ .phase = .at_target, .target = target };

    if (target) |elem| {
        elem.handleWheel(&ctx, mouse);
        if (!ctx.stopped) {
            ctx.phase = .bubbling;
            self.bubbleWheel(elem.parent, &ctx, mouse);
        }
    }
}

fn bubbleMouseDown(_: *Window, start: ?*Element, ctx: *EventContext, mouse: vaxis.Mouse) void {
    var current = start;
    while (current) |elem| : (current = elem.parent) {
        elem.handleMouseDown(ctx, mouse);
        if (ctx.stopped) return;
    }
}

fn bubbleMouseUp(_: *Window, start: ?*Element, ctx: *EventContext, mouse: vaxis.Mouse) void {
    var current = start;
    while (current) |elem| : (current = elem.parent) {
        elem.handleMouseUp(ctx, mouse);
        if (ctx.stopped) return;
    }
}

fn bubbleClick(_: *Window, start: ?*Element, ctx: *EventContext, mouse: vaxis.Mouse) void {
    var current = start;
    while (current) |elem| : (current = elem.parent) {
        elem.handleClick(ctx, mouse);
        if (ctx.stopped) return;
    }
}

fn bubbleMouseMove(_: *Window, start: ?*Element, ctx: *EventContext, mouse: vaxis.Mouse) void {
    var current = start;
    while (current) |elem| : (current = elem.parent) {
        elem.handleMouseMove(ctx, mouse);
        if (ctx.stopped) return;
    }
}

fn bubbleMouseOver(_: *Window, start: ?*Element, ctx: *EventContext, mouse: vaxis.Mouse) void {
    var current = start;
    while (current) |elem| : (current = elem.parent) {
        elem.handleMouseOver(ctx, mouse);
        if (ctx.stopped) return;
    }
}

fn bubbleMouseOut(_: *Window, start: ?*Element, ctx: *EventContext, mouse: vaxis.Mouse) void {
    var current = start;
    while (current) |elem| : (current = elem.parent) {
        elem.handleMouseOut(ctx, mouse);
        if (ctx.stopped) return;
    }
}

fn bubbleWheel(_: *Window, start: ?*Element, ctx: *EventContext, mouse: vaxis.Mouse) void {
    var current = start;
    while (current) |elem| : (current = elem.parent) {
        elem.handleWheel(ctx, mouse);
        if (ctx.stopped) return;
    }
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
