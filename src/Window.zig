const std = @import("std");
const vaxis = @import("vaxis");

const Element = @import("element/Element.zig");
const Root = @import("element/Root.zig");
const Buffer = @import("Buffer.zig");
const AppContext = @import("AppContext.zig");
const Screen = @import("Screen.zig");
const events = @import("events/mod.zig");
const EventContext = events.EventContext;

const Allocator = std.mem.Allocator;

const Window = @This();

const Options = struct {
    keyPressFn: ?*const fn (app_ctx: *AppContext, ctx: *EventContext, key: vaxis.Key) void = null,
    focusFn: ?*const fn (element: ?*Element) void = null,
    blurFn: ?*const fn (element: ?*Element) void = null,
    app_context: *AppContext,
};

alloc: Allocator,

needs_draw: std.atomic.Value(bool) = std.atomic.Value(bool).init(true),

root: *Root,

size: vaxis.Winsize,
screen: *Screen,

keyPressFn: ?*const fn (app_ctx: *AppContext, ctx: *EventContext, key: vaxis.Key) void,
focusFn: ?*const fn (element: ?*Element) void,
blurFn: ?*const fn (element: ?*Element) void,

app_context: *AppContext,

focused: ?*Element = null,
focus_path: std.ArrayListUnmanaged(*Element) = .{},

pub fn init(alloc: Allocator, screen: *Screen, opts: Options) !Window {
    const root = try Root.create(alloc);
    errdefer root.destroy(alloc);

    return .{
        .app_context = opts.app_context,
        .keyPressFn = opts.keyPressFn,
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
    const buffer = screen.writeBuffer();

    const size = self.size;
    if (buffer.width != size.cols or buffer.height != size.rows) {
        try screen.resizeWriteBuffer(self.alloc, size);
    }

    try self.root.element.update();
    self.root.element.draw(buffer);

    screen.swapWrite();
}

pub fn handleKeyPress(self: *Window, key: vaxis.Key) !void {
    var event_ctx = EventContext{
        .phase = .capturing,
        .target = self.focused,
    };

    if (self.keyPressFn) |callback| {
        callback(self.app_context, &event_ctx, key);
    }

    if (event_ctx.stopped) return;

    const target = self.focused orelse return;

    event_ctx.phase = .capturing;
    for (self.focus_path.items) |element| {
        if (element == target) continue;
        if (element.keyPressFn) |handler| {
            handler(element, &event_ctx, key);
        }
        if (event_ctx.stopped) return;
    }

    event_ctx.phase = .at_target;
    if (target.keyPressFn) |handler| {
        handler(target, &event_ctx, key);
    }
    if (event_ctx.stopped) return;

    event_ctx.phase = .bubbling;
    var i: usize = self.focus_path.items.len;
    while (i > 0) {
        i -= 1;
        const element = self.focus_path.items[i];
        if (element == target) continue;
        if (element.keyPressFn) |handler| {
            handler(element, &event_ctx, key);
        }
        if (event_ctx.stopped) return;
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
