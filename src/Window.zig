const std = @import("std");
const vaxis = @import("vaxis");

const Element = @import("element/Element.zig");
const Root = @import("element/Root.zig");
const Buffer = @import("Buffer.zig");
const AppContext = @import("AppContext.zig");
const Screen = @import("Screen.zig");
const HitGrid = @import("HitGrid.zig");
const events = @import("events/mod.zig");
const EventContext = events.EventContext;
const Event = events.Event;

const Allocator = std.mem.Allocator;

const Window = @This();

const Options = struct {
    keyPressFn: ?*const fn (app_ctx: *AppContext, ctx: *EventContext, key: vaxis.Key) void = null,
    keyReleaseFn: ?*const fn (app_ctx: *AppContext, ctx: *EventContext, key: vaxis.Key) void = null,
    focusFn: ?*const fn (app_ctx: *AppContext) void = null,
    blurFn: ?*const fn (app_ctx: *AppContext) void = null,
    app_context: *AppContext,
};

alloc: Allocator,

needs_draw: std.atomic.Value(bool) = std.atomic.Value(bool).init(true),

root: *Root,

size: vaxis.Winsize,
screen: *Screen,

keyPressFn: ?*const fn (app_ctx: *AppContext, ctx: *EventContext, key: vaxis.Key) void,
keyReleaseFn: ?*const fn (app_ctx: *AppContext, ctx: *EventContext, key: vaxis.Key) void,
focusFn: ?*const fn (app_ctx: *AppContext) void,
blurFn: ?*const fn (app_ctx: *AppContext) void,

app_context: *AppContext,

focused: ?*Element = null,
focus_path: std.ArrayListUnmanaged(*Element) = .{},
hit_grid: HitGrid = .{},

pub fn init(alloc: Allocator, screen: *Screen, opts: Options) !Window {
    const root = try Root.create(alloc);
    errdefer root.destroy(alloc);

    Element.initElementMap(alloc);

    return .{
        .app_context = opts.app_context,
        .keyPressFn = opts.keyPressFn,
        .keyReleaseFn = opts.keyReleaseFn,
        .focusFn = opts.focusFn,
        .blurFn = opts.blurFn,
        .screen = screen,
        .alloc = alloc,
        .root = root,
        .size = .{ .cols = 0, .rows = 0, .x_pixel = 0, .y_pixel = 0 },
    };
}

pub fn deinit(self: *Window) void {
    self.focus_path.deinit(self.alloc);
    self.hit_grid.deinit(self.alloc);
    Element.deinitElementMap();
    self.root.destroy(self.alloc);
}

pub fn setContext(self: *Window, ctx: *AppContext) void {
    self.root.element.setContext(ctx);
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

    try self.root.element.update();
    self.root.element.draw(buffer);

    self.hit_grid.clear();
    self.root.element.hit(&self.hit_grid);
}

pub fn getElementAt(self: *Window, col: u16, row: u16) ?*Element {
    const num = self.hit_grid.get(col, row) orelse return null;
    return Element.getElementByNum(num);
}

pub fn handleEvent(self: *Window, event: Event) !void {
    var ctx = EventContext{
        .phase = .capturing,
        .target = self.focused,
    };

    switch (event) {
        .key_press => |key| self.handleKeyPress(&ctx, key),
        .key_release => |key| self.handleKeyRelease(&ctx, key),
        .blur => self.handleBlur(),
        .focus => self.handleFocus(),
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

pub fn handleKeyPress(self: *Window, ctx: *EventContext, key: vaxis.Key) void {
    if (self.keyPressFn) |callback| {
        callback(self.app_context, ctx, key);
    }
}

pub fn handleKeyRelease(self: *Window, ctx: *EventContext, key: vaxis.Key) void {
    if (self.keyReleaseFn) |callback| {
        callback(self.app_context, ctx, key);
    }
}

pub fn handleFocus(self: *Window) void {
    if (self.focusFn) |callback| {
        callback(self.app_context);
    }
}

pub fn handleBlur(self: *Window) void {
    if (self.blurFn) |callback| {
        callback(self.app_context);
    }
}

pub fn setFocus(self: *Window, element: ?*Element) void {
    if (self.focused == element) return;

    const previous = self.focused;

    if (previous) |prev| {
        if (prev.blurFn) |blurFn| {
            blurFn(prev);
        }
    }
    if (self.blurFn) |blurFn| {
        blurFn(previous);
    }

    self.focused = element;
    self.rebuildFocusPath();

    if (element) |elem| {
        if (elem.focusFn) |focusFn| {
            focusFn(elem);
        }
    }
    if (self.focusFn) |focusFn| {
        focusFn(element);
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
