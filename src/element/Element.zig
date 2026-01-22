pub const Element = @This();

const std = @import("std");
const vaxis = @import("vaxis");

const Loop = @import("../Loop.zig");
pub const Tick = Loop.Tick;
pub const Timer = @import("Timer.zig");
const AnimationMod = @import("Animation.zig");
pub const Animation = AnimationMod.Animation;
pub const BaseAnimation = AnimationMod.BaseAnimation;
const Buffer = @import("../Buffer.zig");
const HitGrid = @import("../HitGrid.zig");

pub const AppContext = @import("../AppContext.zig");
const events = @import("../events/mod.zig");
pub const EventContext = events.EventContext;
const Event = events.Event;

pub const Childrens = std.ArrayListUnmanaged(*Element);
pub const ElementMap = std.AutoHashMap(u64, *Element);

var global_counter: std.atomic.Value(u64) = .init(0);
var element_map: ?ElementMap = null;

pub fn initElementMap(alloc: std.mem.Allocator) void {
    if (element_map == null) {
        element_map = ElementMap.init(alloc);
    }
}

pub fn deinitElementMap() void {
    if (element_map) |*map| {
        map.deinit();
        element_map = null;
    }
}

pub fn getElementByNum(num: u64) ?*Element {
    if (element_map) |map| {
        return map.get(num);
    }
    return null;
}

pub fn registerElement(elem: *Element) void {
    if (element_map) |*map| {
        map.put(elem.num, elem) catch {};
    }
}

fn unregisterElement(elem: *Element) void {
    if (element_map) |*map| {
        _ = map.remove(elem.num);
    }
}

alloc: std.mem.Allocator,
id: []const u8,
num: u64,
visible: bool = true,
zIndex: usize = 0,
removed: bool = false,
opacity: f32 = 1.0,
childrens: ?Childrens = null,
parent: ?*Element = null,
x: u16 = 0,
y: u16 = 0,
width: u16 = 0,
height: u16 = 0,
context: ?*AppContext = null,

userdata: ?*anyopaque = null,
updateFn: ?*const fn (element: *Element, time: std.time.Instant) void = null,
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

pub fn draw(self: *Element, buffer: *Buffer) void {
    if (!self.visible) return;

    if (self.drawFn) |callback| {
        callback(self, buffer);
    }

    if (self.childrens) |*children| {
        std.mem.sort(*Element, children.items, {}, zIndexLessThanValue);
        for (children.items) |child| {
            child.draw(buffer);
        }
    }
}

fn zIndexLessThanValue(_: void, a: *Element, b: *Element) bool {
    return a.zIndex < b.zIndex;
}

pub fn hit(self: *Element, hit_grid: *HitGrid) void {
    if (!self.visible) return;

    if (self.hitGridFn) |callback| {
        callback(self, hit_grid);
    }

    if (self.childrens) |*children| {
        std.mem.sort(*Element, children.items, {}, zIndexLessThanValue);
        for (children.items) |child| {
            child.hit(hit_grid);
        }
    }
}

pub fn update(self: *Element) !void {
    if (self.updateFn) |callback| {
        callback(self, try std.time.Instant.now());
    }

    if (self.childrens) |*childrens| {
        for (childrens.items) |child| {
            try child.update();
        }
    }
}

pub fn getContext(self: *Element) ?*AppContext {
    return self.context;
}

pub fn setContext(self: *Element, ctx: *AppContext) void {
    self.context = ctx;

    if (self.childrens) |*childrens| {
        for (childrens.items) |child| {
            child.setContext(ctx);
        }
    }
}

pub const Opts = struct {
    id: ?[]const u8 = null,
    visible: bool = true,
    zIndex: usize = 0,
    opacity: f32 = 1.0,
    x: u16 = 0,
    y: u16 = 0,
    width: u16 = 0,
    height: u16 = 0,
    userdata: ?*anyopaque = null,
    updateFn: ?*const fn (element: *Element, time: std.time.Instant) void = null,
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

pub fn init(alloc: std.mem.Allocator, opts: Opts) Element {
    const num = global_counter.fetchAdd(1, .monotonic);
    var id_buf: [32]u8 = undefined;
    const generated_id = std.fmt.bufPrint(&id_buf, "element-{d}", .{num}) catch "element-?";

    return .{
        .alloc = alloc,
        .id = opts.id orelse generated_id,
        .num = num,
        .visible = opts.visible,
        .zIndex = opts.zIndex,
        .opacity = opts.opacity,
        .x = opts.x,
        .y = opts.y,
        .width = opts.width,
        .height = opts.height,
        .userdata = opts.userdata,
        .updateFn = opts.updateFn,
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

pub fn remove(self: *Element) void {
    if (self.removed) return;
    self.removed = true;

    unregisterElement(self);

    if (self.parent) |parent| {
        if (parent.childrens) |*siblings| {
            for (siblings.items, 0..) |child, i| {
                if (std.mem.eql(u8, child.id, self.id)) {
                    _ = siblings.orderedRemove(i);
                    break;
                }
            }
        }
        self.parent = null;
    }

    if (self.childrens) |*children| {
        for (children.items) |child| {
            child.parent = null;
            child.remove();
        }
        children.deinit(self.alloc);
        self.childrens = null;
    }

    if (self.removeFn) |removeFn| {
        removeFn(self);
    }
}

pub fn addChild(self: *Element, child: *Element) !void {
    if (self.childrens == null) {
        self.childrens = .{};
    }
    child.parent = self;

    registerElement(child);

    if (self.context) |ctx| {
        child.setContext(ctx);
    }

    try self.childrens.?.append(self.alloc, child);
}

pub fn removeChild(self: *Element, id: []const u8) void {
    if (self.childrens) |*children| {
        for (children.items) |child| {
            if (std.mem.eql(u8, child.id, id)) {
                child.remove();
                return;
            }
        }
    }
}

pub fn getChildById(self: *Element, id: []const u8) ?*Element {
    if (self.childrens) |*children| {
        for (children.items) |child| {
            if (std.mem.eql(u8, child.id, id)) {
                return child;
            }
        }
    }
    return null;
}

pub fn getChildrenSortedByZIndex(self: *Element, result: *std.ArrayList(*Element)) !void {
    if (self.childrens) |*children| {
        result.clearRetainingCapacity();
        try result.ensureTotalCapacity(children.items.len);
        for (children.items) |child| {
            try result.append(child);
        }
        std.mem.sort(*Element, result.items, {}, zIndexLessThan);
    }
}

fn zIndexLessThan(_: void, a: *Element, b: *Element) bool {
    return a.zIndex < b.zIndex;
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
