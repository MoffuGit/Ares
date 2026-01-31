pub const Animation = @import("Animation.zig");
pub const Timer = @import("Timer.zig");
pub const Style = @import("Style.zig");
pub const Node = @import("Node.zig");
pub const Scrollable = @import("Scrollable.zig");

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
const Mouse = events.Mouse;
const Allocator = std.mem.Allocator;

pub const Childrens = struct {
    by_order: std.ArrayList(*Element) = .{},
    by_z_index: std.ArrayList(*Element) = .{},

    pub fn len(self: *Childrens) usize {
        return self.by_order.items.len;
    }

    pub fn deinit(self: *Childrens, alloc: std.mem.Allocator) void {
        self.by_order.deinit(alloc);
        self.by_z_index.deinit(alloc);
    }

    pub fn add(self: *Childrens, child: *Element, alloc: Allocator) !void {
        try self.by_order.append(alloc, child);
        try self.insertByZIndex(child, alloc);
    }

    pub fn insert(self: *Childrens, child: *Element, index: usize, alloc: Allocator) !void {
        try self.by_order.insert(alloc, index, child);
        try self.insertByZIndex(child, alloc);
    }

    fn insertByZIndex(self: *Childrens, child: *Element, alloc: Allocator) !void {
        const insert_idx = blk: {
            var idx: usize = 0;
            for (self.by_z_index.items) |c| {
                if (c.zIndex > child.zIndex) break :blk idx;
                idx += 1;
            }
            break :blk idx;
        };
        try self.by_z_index.insert(alloc, insert_idx, child);
    }

    pub fn remove(self: *Childrens, num: u64) ?*Element {
        var removed_child: ?*Element = null;

        for (self.by_order.items, 0..) |child, idx| {
            if (num == child.num) {
                removed_child = self.by_order.orderedRemove(idx);
                break;
            }
        }

        for (self.by_z_index.items, 0..) |child, idx| {
            if (num == child.num) {
                _ = self.by_z_index.orderedRemove(idx);
                break;
            }
        }

        return removed_child;
    }
};

pub const Layout = struct {
    left: u16 = 0,
    top: u16 = 0,
    right: u16 = 0,
    bottom: u16 = 0,
    width: u16 = 0,
    height: u16 = 0,
    direction: Node.yoga.YGDirection = Node.yoga.YGDirectionInherit,
    had_overflow: bool = false,
    margin: Edges = .{},
    border: Edges = .{},
    padding: Edges = .{},

    pub const Edges = struct {
        left: u16 = 0,
        top: u16 = 0,
        right: u16 = 0,
        bottom: u16 = 0,
    };
};

pub const EventType = enum {
    remove,
    key_press,
    key_release,
    focus,
    blur,
    mouse_down,
    mouse_up,
    click,
    mouse_move,
    mouse_enter,
    mouse_leave,
    mouse_over,
    mouse_out,
    wheel,
    drag,
    drag_end,
    resize,
};

pub const EventData = union(EventType) {
    remove: void,
    key_press: struct { ctx: *EventContext, key: vaxis.Key },
    key_release: struct { ctx: *EventContext, key: vaxis.Key },
    focus: void,
    blur: void,
    mouse_down: struct { ctx: *EventContext, mouse: Mouse },
    mouse_up: struct { ctx: *EventContext, mouse: Mouse },
    click: struct { ctx: *EventContext, mouse: Mouse },
    mouse_move: struct { ctx: *EventContext, mouse: Mouse },
    mouse_enter: Mouse,
    mouse_leave: Mouse,
    mouse_over: struct { ctx: *EventContext, mouse: Mouse },
    mouse_out: struct { ctx: *EventContext, mouse: Mouse },
    wheel: struct { ctx: *EventContext, mouse: Mouse },
    drag: struct { ctx: *EventContext, mouse: Mouse },
    drag_end: struct { ctx: *EventContext, mouse: Mouse },
    resize: struct { width: u16, height: u16 },
};

pub const Callback = *const fn (element: *Element, data: EventData) void;
pub const CallbackList = std.ArrayListUnmanaged(Callback);
pub const EventListeners = std.EnumArray(EventType, CallbackList);

pub const DrawFn = *const fn (element: *Element, buffer: *Buffer) void;
pub const HitFn = *const fn (element: *Element, hit_grid: *HitGrid) void;

pub const UpdateFn = *const fn (element: *Element) void;

pub const Options = struct {
    id: ?[]const u8 = null,
    visible: bool = true,
    zIndex: usize = 0,
    style: Style = .{},
    userdata: ?*anyopaque = null,
    beforeDrawFn: ?DrawFn = null,
    drawFn: ?DrawFn = null,
    afterDrawFn: ?DrawFn = null,
    beforeHitFn: ?HitFn = null,
    hitFn: ?HitFn = null,
    afterHitFn: ?HitFn = null,
    updateFn: ?UpdateFn = null,
};

pub const Element = @This();

alloc: Allocator,
id: []const u8,
num: u64,

node: Node,

visible: bool = true,
removed: bool = true,
focused: bool = false,
hovered: bool = false,
dragging: bool = false,

zIndex: usize = 0,

childrens: ?Childrens = null,
parent: ?*Element = null,

layout: Layout = .{},

style: Style = .{},

context: ?*AppContext = null,

userdata: ?*anyopaque = null,

updateFn: ?UpdateFn = null,

drawFn: ?DrawFn = null,
hitFn: ?HitFn = null,

beforeDrawFn: ?DrawFn = null,
afterDrawFn: ?DrawFn = null,
beforeHitFn: ?HitFn = null,
afterHitFn: ?HitFn = null,

listeners: EventListeners = EventListeners.initFill(.{}),

pub fn init(alloc: std.mem.Allocator, opts: Options) Element {
    const num = element_counter.fetchAdd(1, .monotonic);
    var id_buf: [32]u8 = undefined;
    const generated_id = std.fmt.bufPrint(&id_buf, "element-{}", .{num}) catch "element-?";

    const node = Node.init(num);

    opts.style.apply(node);

    return .{
        .alloc = alloc,
        .id = opts.id orelse generated_id,
        .num = num,
        .visible = opts.visible,
        .zIndex = opts.zIndex,
        .style = opts.style,
        .userdata = opts.userdata,
        .beforeDrawFn = opts.beforeDrawFn,
        .afterDrawFn = opts.afterDrawFn,
        .beforeHitFn = opts.beforeHitFn,
        .afterHitFn = opts.afterHitFn,
        .drawFn = opts.drawFn,
        .hitFn = opts.hitFn,
        .updateFn = opts.updateFn,
        .node = node,
    };
}

pub fn addEventListener(self: *Element, event_type: EventType, callback: Callback) !void {
    try self.listeners.getPtr(event_type).append(self.alloc, callback);
}

pub fn dispatchEvent(self: *Element, data: EventData) void {
    const callbacks = self.listeners.get(@as(EventType, data));
    for (callbacks.items) |callback| {
        callback(self, data);
    }
}

pub fn syncLayout(self: *Element) void {
    const old_width = self.layout.width;
    const old_height = self.layout.height;

    const new_width = self.node.getLayoutWidth();
    const new_height = self.node.getLayoutHeight();

    const parent_left: u16 = if (self.parent) |p| p.layout.left else 0;
    const parent_top: u16 = if (self.parent) |p| p.layout.top else 0;

    self.layout = .{
        .left = parent_left + self.node.getLayoutLeft(),
        .top = parent_top + self.node.getLayoutTop(),
        .right = self.node.getLayoutRight(),
        .bottom = self.node.getLayoutBottom(),
        .width = new_width,
        .height = new_height,
        .direction = self.node.getLayoutDirection(),
        .had_overflow = self.node.getLayoutHadOverflow(),
        .margin = .{
            .left = self.node.getLayoutMargin(.left),
            .top = self.node.getLayoutMargin(.top),
            .right = self.node.getLayoutMargin(.right),
            .bottom = self.node.getLayoutMargin(.bottom),
        },
        .border = .{
            .left = self.node.getLayoutBorder(.left),
            .top = self.node.getLayoutBorder(.top),
            .right = self.node.getLayoutBorder(.right),
            .bottom = self.node.getLayoutBorder(.bottom),
        },
        .padding = .{
            .left = self.node.getLayoutPadding(.left),
            .top = self.node.getLayoutPadding(.top),
            .right = self.node.getLayoutPadding(.right),
            .bottom = self.node.getLayoutPadding(.bottom),
        },
    };

    if (old_width != new_width or old_height != new_height) {
        self.dispatchEvent(.{ .resize = .{ .width = new_width, .height = new_height } });
    }
}

pub fn deinit(self: *Element) void {
    if (self.childrens) |*childrens| {
        childrens.deinit(self.alloc);
        self.childrens = null;
    }

    for (&self.listeners.values) |*list| {
        list.deinit(self.alloc);
    }

    self.node.deinit();
}

pub fn update(self: *Element) void {
    if (self.updateFn) |callback| {
        callback(self);
    }

    if (self.childrens) |*childrens| {
        for (childrens.by_order.items) |child| {
            child.update();
        }
    }
}

pub fn draw(self: *Element, buffer: *Buffer) void {
    if (!self.visible) return;

    if (self.beforeDrawFn) |callback| {
        callback(self, buffer);
    }

    if (self.drawFn) |callback| {
        callback(self, buffer);
    }

    if (self.childrens) |*childrens| {
        for (childrens.by_z_index.items) |child| {
            child.draw(buffer);
        }
    }

    if (self.afterDrawFn) |callback| {
        callback(self, buffer);
    }
}

pub fn hit(self: *Element, hit_grid: *HitGrid) void {
    if (!self.visible) return;

    if (self.beforeHitFn) |callback| {
        callback(self, hit_grid);
    }

    if (self.hitFn) |callback| {
        callback(self, hit_grid);
    }

    if (self.childrens) |*childrens| {
        for (childrens.by_z_index.items) |child| {
            child.hit(hit_grid);
        }
    }

    if (self.afterHitFn) |callback| {
        callback(self, hit_grid);
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

    if (self.parent) |parent| {
        parent.removeChild(self.num);
    } else {
        if (self.context) |ctx| {
            ctx.window.removeElement(self.num);
        }

        self.context = null;
        self.removed = true;

        self.dispatchEvent(.{ .remove = {} });
    }

    if (self.childrens) |*childrens| {
        for (childrens.by_order.items) |child| {
            child.remove();
        }
    }
}

pub fn addChild(self: *Element, child: *Element) !void {
    if (self.childrens == null) {
        self.childrens = .{};
    }

    child.parent = self;
    child.removed = false;

    if (self.context) |ctx| {
        try child.setContext(ctx);
    }

    try self.childrens.?.add(child, self.alloc);

    self.node.insertChild(child.node, self.childrens.?.len() - 1);
}

pub fn insertChild(self: *Element, child: *Element, index: usize) !void {
    if (self.childrens == null) {
        self.childrens = .{};
    }

    child.parent = self;
    child.removed = false;

    if (self.context) |ctx| {
        try child.setContext(ctx);
    }

    try self.childrens.?.insert(child, index, self.alloc);

    self.node.insertChild(child.node, index);
}

pub fn removeChild(self: *Element, num: u64) void {
    if (self.childrens) |*childrens| {
        const child = childrens.remove(num) orelse return;

        self.node.removeChild(child.node);

        if (child.context) |ctx| {
            ctx.window.removeElement(num);
        }

        child.parent = null;
        child.context = null;
        child.removed = true;

        child.dispatchEvent(.{ .remove = {} });
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
    self.dispatchEvent(.{ .key_press = .{ .ctx = ctx, .key = key } });
}

pub fn handleKeyRelease(self: *Element, ctx: *EventContext, key: vaxis.Key) void {
    self.dispatchEvent(.{ .key_release = .{ .ctx = ctx, .key = key } });
}

pub fn handleFocus(self: *Element) void {
    self.dispatchEvent(.{ .focus = {} });
}

pub fn handleBlur(self: *Element) void {
    self.dispatchEvent(.{ .blur = {} });
}

pub fn handleResize(self: *Element, width: u16, height: u16) void {
    self.dispatchEvent(.{ .resize = .{ .width = width, .height = height } });
}

pub fn isAncestorOf(self: *Element, other: *Element) bool {
    var current: ?*Element = other.parent;
    while (current) |elem| : (current = elem.parent) {
        if (elem == self) return true;
    }
    return false;
}

test "add child to element" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var parent = Element.init(alloc, .{});
    defer parent.deinit();

    var child = Element.init(alloc, .{});
    defer child.deinit();

    try parent.addChild(&child);

    try testing.expect(child.parent == &parent);
    try testing.expect(parent.childrens != null);
    try testing.expectEqual(@as(usize, 1), parent.childrens.?.by_order.items.len);
    try testing.expectEqual(@as(usize, 1), parent.childrens.?.by_z_index.items.len);
    try testing.expect(parent.childrens.?.by_order.items[0] == &child);
}

test "add multiple children with z-index ordering" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var parent = Element.init(alloc, .{});
    defer parent.deinit();

    var child1 = Element.init(alloc, .{ .zIndex = 2 });
    defer child1.deinit();

    var child2 = Element.init(alloc, .{ .zIndex = 0 });
    defer child2.deinit();

    var child3 = Element.init(alloc, .{ .zIndex = 1 });
    defer child3.deinit();

    try parent.addChild(&child1);
    try parent.addChild(&child2);
    try parent.addChild(&child3);

    try testing.expectEqual(@as(usize, 3), parent.childrens.?.by_order.items.len);
    try testing.expectEqual(@as(usize, 3), parent.childrens.?.by_z_index.items.len);

    try testing.expect(parent.childrens.?.by_order.items[0] == &child1);
    try testing.expect(parent.childrens.?.by_order.items[1] == &child2);
    try testing.expect(parent.childrens.?.by_order.items[2] == &child3);

    try testing.expect(parent.childrens.?.by_z_index.items[0] == &child2);
    try testing.expect(parent.childrens.?.by_z_index.items[1] == &child3);
    try testing.expect(parent.childrens.?.by_z_index.items[2] == &child1);
}

test "remove child from element" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var parent = Element.init(alloc, .{});
    defer parent.deinit();

    var child = Element.init(alloc, .{});
    defer child.deinit();

    try parent.addChild(&child);
    try testing.expectEqual(@as(usize, 1), parent.childrens.?.by_order.items.len);

    parent.removeChild(child.num);

    try testing.expectEqual(@as(usize, 0), parent.childrens.?.by_order.items.len);
    try testing.expectEqual(@as(usize, 0), parent.childrens.?.by_z_index.items.len);
    try testing.expect(child.parent == null);
    try testing.expect(child.removed == true);
}

test "remove middle child preserves order" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var parent = Element.init(alloc, .{});
    defer parent.deinit();

    var child1 = Element.init(alloc, .{});
    defer child1.deinit();

    var child2 = Element.init(alloc, .{});
    defer child2.deinit();

    var child3 = Element.init(alloc, .{});
    defer child3.deinit();

    try parent.addChild(&child1);
    try parent.addChild(&child2);
    try parent.addChild(&child3);

    parent.removeChild(child2.num);

    try testing.expectEqual(@as(usize, 2), parent.childrens.?.by_order.items.len);
    try testing.expect(parent.childrens.?.by_order.items[0] == &child1);
    try testing.expect(parent.childrens.?.by_order.items[1] == &child3);
}

test "element remove via parent" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var parent = Element.init(alloc, .{});
    defer parent.deinit();

    var child = Element.init(alloc, .{});
    defer child.deinit();

    try parent.addChild(&child);

    child.remove();

    try testing.expectEqual(@as(usize, 0), parent.childrens.?.by_order.items.len);
    try testing.expect(child.parent == null);
    try testing.expect(child.removed == true);
}

test "isAncestorOf" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var grandparent = Element.init(alloc, .{});
    defer grandparent.deinit();

    var parent = Element.init(alloc, .{});
    defer parent.deinit();

    var child = Element.init(alloc, .{});
    defer child.deinit();

    try grandparent.addChild(&parent);
    try parent.addChild(&child);

    try testing.expect(grandparent.isAncestorOf(&child) == true);
    try testing.expect(grandparent.isAncestorOf(&parent) == true);
    try testing.expect(parent.isAncestorOf(&child) == true);
    try testing.expect(child.isAncestorOf(&grandparent) == false);
    try testing.expect(child.isAncestorOf(&parent) == false);
}

test "getChildById" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var parent = Element.init(alloc, .{});
    defer parent.deinit();

    var child1 = Element.init(alloc, .{ .id = "first" });
    defer child1.deinit();

    var child2 = Element.init(alloc, .{ .id = "second" });
    defer child2.deinit();

    try parent.addChild(&child1);
    try parent.addChild(&child2);

    const found = parent.getChildById("second");
    try testing.expect(found != null);
    try testing.expect(found.? == &child2);

    const not_found = parent.getChildById("nonexistent");
    try testing.expect(not_found == null);
}

test "remove nonexistent child does nothing" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var parent = Element.init(alloc, .{});
    defer parent.deinit();

    var child = Element.init(alloc, .{});
    defer child.deinit();

    try parent.addChild(&child);

    parent.removeChild(999999);

    try testing.expectEqual(@as(usize, 1), parent.childrens.?.by_order.items.len);
}
