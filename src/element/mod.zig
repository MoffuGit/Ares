pub const Box = @import("Box.zig");
pub const Animation = @import("Animation.zig");
pub const Timer = @import("Timer.zig");

pub var element_counter: std.atomic.Value(u64) = .init(0);

const std = @import("std");
const vaxis = @import("vaxis");

const Loop = @import("../Loop.zig");
const Tick = Loop.Tick;
const Buffer = @import("../Buffer.zig");
const HitGrid = @import("../HitGrid.zig");

pub const AppContext = @import("../AppContext.zig");
const events = @import("../events/mod.zig");
pub const EventContext = events.EventContext;
const Event = events.Event;

pub const Childrens = struct {
    by_order: std.ArrayList(*Element) = .{},
    by_z_index: std.ArrayList(*Element) = .{},

    pub fn deinit(self: *Childrens, alloc: std.mem.Allocator) void {
        self.by_order.deinit(alloc);
        self.by_z_index.deinit(alloc);
    }
};

pub const Options = struct {
    id: ?[]const u8 = null,
    visible: bool = true,
    zIndex: usize = 0,
    x: u16 = 0,
    y: u16 = 0,
    width: u16 = 0,
    height: u16 = 0,
    userdata: ?*anyopaque = null,
    drawFn: ?*const fn (element: *Element, buffer: *Buffer) void = null,
    removeFn: ?*const fn (element: *Element) void = null,
    keyPressFn: ?*const fn (element: *Element, ctx: *EventContext, key: vaxis.Key) void = null,
    focusFn: ?*const fn (element: *Element) void = null,
    blurFn: ?*const fn (element: *Element) void = null,
    hitGridFn: ?*const fn (element: *Element, hit_grid: *HitGrid) void = null,
    mouseDownFn: ?*const fn (element: *Element, ctx: *EventContext, mouse: vaxis.Mouse) void = null,
    mouseUpFn: ?*const fn (element: *Element, ctx: *EventContext, mouse: vaxis.Mouse) void = null,
    clickFn: ?*const fn (element: *Element, ctx: *EventContext, mouse: vaxis.Mouse) void = null,
    mouseMoveFn: ?*const fn (element: *Element, ctx: *EventContext, mouse: vaxis.Mouse) void = null,
    mouseEnterFn: ?*const fn (element: *Element, mouse: vaxis.Mouse) void = null,
    mouseLeaveFn: ?*const fn (element: *Element, mouse: vaxis.Mouse) void = null,
    mouseOverFn: ?*const fn (element: *Element, ctx: *EventContext, mouse: vaxis.Mouse) void = null,
    mouseOutFn: ?*const fn (element: *Element, ctx: *EventContext, mouse: vaxis.Mouse) void = null,
    wheelFn: ?*const fn (element: *Element, ctx: *EventContext, mouse: vaxis.Mouse) void = null,
};

pub const Element = @This();

alloc: std.mem.Allocator,
id: []const u8,
num: u64,

visible: bool = true,
removed: bool = false,

zIndex: usize = 0,

childrens: ?Childrens = null,
parent: ?*Element = null,

x: u16 = 0,
y: u16 = 0,
width: u16 = 0,
height: u16 = 0,

context: ?*AppContext = null,

userdata: ?*anyopaque = null,
drawFn: ?*const fn (element: *Element, buffer: *Buffer) void = null,
removeFn: ?*const fn (element: *Element) void = null,
keyPressFn: ?*const fn (element: *Element, ctx: *EventContext, key: vaxis.Key) void = null,
keyReleaseFn: ?*const fn (element: *Element, ctx: *EventContext, key: vaxis.Key) void = null,
focusFn: ?*const fn (element: *Element) void = null,
blurFn: ?*const fn (element: *Element) void = null,
hitGridFn: ?*const fn (element: *Element, hit_grid: *HitGrid) void = null,
mouseDownFn: ?*const fn (element: *Element, ctx: *EventContext, mouse: vaxis.Mouse) void = null,
mouseUpFn: ?*const fn (element: *Element, ctx: *EventContext, mouse: vaxis.Mouse) void = null,
clickFn: ?*const fn (element: *Element, ctx: *EventContext, mouse: vaxis.Mouse) void = null,
mouseMoveFn: ?*const fn (element: *Element, ctx: *EventContext, mouse: vaxis.Mouse) void = null,
mouseEnterFn: ?*const fn (element: *Element, mouse: vaxis.Mouse) void = null,
mouseLeaveFn: ?*const fn (element: *Element, mouse: vaxis.Mouse) void = null,
mouseOverFn: ?*const fn (element: *Element, ctx: *EventContext, mouse: vaxis.Mouse) void = null,
mouseOutFn: ?*const fn (element: *Element, ctx: *EventContext, mouse: vaxis.Mouse) void = null,
wheelFn: ?*const fn (element: *Element, ctx: *EventContext, mouse: vaxis.Mouse) void = null,

pub fn init(alloc: std.mem.Allocator, opts: Options) Element {
    const num = element_counter.fetchAdd(1, .monotonic);
    var id_buf: [32]u8 = undefined;
    const generated_id = std.fmt.bufPrint(&id_buf, "element-{d}", .{num}) catch "element-?";

    return .{
        .alloc = alloc,
        .id = opts.id orelse generated_id,
        .num = num,
        .visible = opts.visible,
        .zIndex = opts.zIndex,
        .x = opts.x,
        .y = opts.y,
        .width = opts.width,
        .height = opts.height,
        .userdata = opts.userdata,
        .drawFn = opts.drawFn,
        .removeFn = opts.removeFn,
        .keyPressFn = opts.keyPressFn,
        .focusFn = opts.focusFn,
        .blurFn = opts.blurFn,
        .hitGridFn = opts.hitGridFn,
        .mouseDownFn = opts.mouseDownFn,
        .mouseUpFn = opts.mouseUpFn,
        .clickFn = opts.clickFn,
        .mouseMoveFn = opts.mouseMoveFn,
        .mouseEnterFn = opts.mouseEnterFn,
        .mouseLeaveFn = opts.mouseLeaveFn,
        .mouseOverFn = opts.mouseOverFn,
        .mouseOutFn = opts.mouseOutFn,
        .wheelFn = opts.wheelFn,
    };
}

pub fn deinit(self: *Element) void {
    if (self.childrens) |*childrens| {
        childrens.deinit(self.alloc);
        self.childrens = null;
    }
}

pub fn draw(self: *Element, buffer: *Buffer) void {
    if (!self.visible) return;

    if (self.drawFn) |callback| {
        callback(self, buffer);
    }

    if (self.childrens) |*childrens| {
        for (childrens.by_z_index.items) |child| {
            child.draw(buffer);
        }
    }
}

pub fn hit(self: *Element, hit_grid: *HitGrid) void {
    if (!self.visible) return;

    if (self.hitGridFn) |callback| {
        callback(self, hit_grid);
    }

    if (self.childrens) |*childrens| {
        for (childrens.by_z_index.items) |child| {
            child.hit(hit_grid);
        }
    }
}

pub fn setContext(self: *Element, ctx: *AppContext) !void {
    self.context = ctx;
    try ctx.window.addElement(self);

    if (self.childrens) |*childrens| {
        for (childrens.by_order.items) |child| {
            try child.setContext(ctx);
        }
    }
}

pub fn remove(self: *Element) void {
    if (self.removed) return;
    self.removed = true;

    if (self.parent) |parent| {
        if (parent.childrens) |*siblings| {
            for (siblings.by_order.items, 0..) |child, i| {
                if (std.mem.eql(u8, child.id, self.id)) {
                    _ = siblings.by_order.orderedRemove(i);
                    break;
                }
            }
            for (siblings.by_z_index.items, 0..) |child, i| {
                if (std.mem.eql(u8, child.id, self.id)) {
                    _ = siblings.by_z_index.orderedRemove(i);
                    break;
                }
            }
        }
        self.parent = null;
    }

    if (self.childrens) |*childrens| {
        for (childrens.by_order.items) |child| {
            child.parent = null;
            child.remove();
        }
    }

    if (self.context) |ctx| {
        ctx.window.removeElement(self.num);
    }

    self.deinit();

    if (self.removeFn) |removeFn| {
        removeFn(self);
    }
}

pub fn addChild(self: *Element, child: *Element) !void {
    if (self.childrens == null) {
        self.childrens = .{};
    }
    child.parent = self;

    if (self.context) |ctx| {
        try child.setContext(ctx);
    }

    try self.childrens.?.by_order.append(self.alloc, child);

    const insert_idx = blk: {
        var idx: usize = 0;
        for (self.childrens.?.by_z_index.items) |c| {
            if (c.zIndex > child.zIndex) break :blk idx;
            idx += 1;
        }
        break :blk idx;
    };
    try self.childrens.?.by_z_index.insert(self.alloc, insert_idx, child);
}

pub fn removeChild(self: *Element, id: []const u8) void {
    if (self.childrens) |*childrens| {
        for (childrens.by_order.items) |child| {
            if (std.mem.eql(u8, child.id, id)) {
                child.remove();
                return;
            }
        }
    }
}

pub fn getChildById(self: *Element, id: []const u8) ?*Element {
    if (self.childrens) |*childrens| {
        for (childrens.by_order.items) |child| {
            if (std.mem.eql(u8, child.id, id)) {
                return child;
            }
        }
    }
    return null;
}

pub fn handleEvent(self: *Element, ctx: *EventContext, event: Event) void {
    switch (event) {
        .key_press => |key| self.handleKeyPress(ctx, key),
        .key_release => |key| self.handleKeyRelease(ctx, key),
        .blur => self.handleBlur(),
        .focus => self.handleFocus(),
        .mouse => {},
    }
}

pub fn handleKeyPress(self: *Element, ctx: *EventContext, key: vaxis.Key) void {
    if (self.keyPressFn) |callback| {
        callback(self, ctx, key);
    }
}

pub fn handleKeyRelease(self: *Element, ctx: *EventContext, key: vaxis.Key) void {
    if (self.keyReleaseFn) |callback| {
        callback(self, ctx, key);
    }
}

pub fn handleFocus(self: *Element) void {
    if (self.focusFn) |callback| {
        callback(self);
    }
}

pub fn handleBlur(self: *Element) void {
    if (self.blurFn) |callback| {
        callback(self);
    }
}

pub fn handleMouseDown(self: *Element, ctx: *EventContext, mouse: vaxis.Mouse) void {
    if (self.mouseDownFn) |callback| callback(self, ctx, mouse);
}

pub fn handleMouseUp(self: *Element, ctx: *EventContext, mouse: vaxis.Mouse) void {
    if (self.mouseUpFn) |callback| callback(self, ctx, mouse);
}

pub fn handleClick(self: *Element, ctx: *EventContext, mouse: vaxis.Mouse) void {
    if (self.clickFn) |callback| callback(self, ctx, mouse);
}

pub fn handleMouseMove(self: *Element, ctx: *EventContext, mouse: vaxis.Mouse) void {
    if (self.mouseMoveFn) |callback| callback(self, ctx, mouse);
}

pub fn handleMouseEnter(self: *Element, mouse: vaxis.Mouse) void {
    if (self.mouseEnterFn) |callback| callback(self, mouse);
}

pub fn handleMouseLeave(self: *Element, mouse: vaxis.Mouse) void {
    if (self.mouseLeaveFn) |callback| callback(self, mouse);
}

pub fn handleMouseOver(self: *Element, ctx: *EventContext, mouse: vaxis.Mouse) void {
    if (self.mouseOverFn) |callback| callback(self, ctx, mouse);
}

pub fn handleMouseOut(self: *Element, ctx: *EventContext, mouse: vaxis.Mouse) void {
    if (self.mouseOutFn) |callback| callback(self, ctx, mouse);
}

pub fn handleWheel(self: *Element, ctx: *EventContext, mouse: vaxis.Mouse) void {
    if (self.wheelFn) |callback| callback(self, ctx, mouse);
}

pub fn isAncestorOf(self: *Element, other: *Element) bool {
    var current: ?*Element = other.parent;
    while (current) |elem| : (current = elem.parent) {
        if (elem == self) return true;
    }
    return false;
}
