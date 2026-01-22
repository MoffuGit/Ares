pub const Root = @This();

const Element = @import("Element.zig");
const Timer = @import("Timer.zig");
const AppContext = Element.AppContext;
const EventContext = Element.EventContext;
const std = @import("std");
const vaxis = @import("vaxis");

const Allocator = std.mem.Allocator;

const Buffer = @import("../Buffer.zig");
const HitGrid = @import("../HitGrid.zig");

const Color = vaxis.Cell.Color;

element: Element,
bg_color: Color = .{ .rgb = .{ 0x1a, 0x1a, 0x2e } },
child_box: ?*Element = null,
child_bg_color: Color = .{ .rgb = .{ 0x16, 0x21, 0x3e } },

pub fn create(alloc: std.mem.Allocator) !*Root {
    const self = try alloc.create(Root);
    self.* = .{
        .element = Element.init(alloc, .{
            .id = "__root__",
            .userdata = self,
            .drawFn = draw,
            .hitGridFn = hitGrid,
            .mouseEnterFn = onMouseEnter,
            .mouseLeaveFn = onMouseLeave,
            .mouseDownFn = onMouseDown,
            .mouseUpFn = onMouseUp,
            .clickFn = onClick,
            .focusFn = onFocus,
            .blurFn = onBlur,
        }),
    };

    const child = try alloc.create(Element);
    child.* = Element.init(alloc, .{
        .id = "test_box",
        .x = 5,
        .y = 3,
        .width = 20,
        .height = 8,
        .userdata = self,
        .drawFn = drawChild,
        .hitGridFn = hitGridChild,
        .mouseEnterFn = onChildMouseEnter,
        .mouseLeaveFn = onChildMouseLeave,
        .mouseDownFn = onChildMouseDown,
        .mouseUpFn = onChildMouseUp,
        .clickFn = onChildClick,
        .wheelFn = onChildWheel,
    });

    try self.element.addChild(child);
    self.child_box = child;

    return self;
}

pub fn destroy(self: *Root, alloc: Allocator) void {
    if (self.child_box) |child| {
        alloc.destroy(child);
    }
    self.element.remove();
    alloc.destroy(self);
}

fn draw(element: *Element, buffer: *Buffer) void {
    const self: *Root = @ptrCast(@alignCast(element.userdata));
    const cell: vaxis.Cell = .{ .style = .{ .bg = self.bg_color } };
    buffer.fill(cell);
}

fn hitGrid(element: *Element, hit_grid: *HitGrid) void {
    hit_grid.fillRect(0, 0, hit_grid.width, hit_grid.height, element.num);
}

fn drawChild(element: *Element, buffer: *Buffer) void {
    const self: *Root = @ptrCast(@alignCast(element.userdata));
    const cell: vaxis.Cell = .{
        .char = .{ .grapheme = " ", .width = 1 },
        .style = .{ .bg = self.child_bg_color },
    };

    var row: u16 = element.y;
    while (row < element.y + element.height) : (row += 1) {
        var col: u16 = element.x;
        while (col < element.x + element.width) : (col += 1) {
            buffer.setCell(col, row, cell);
        }
    }
}

fn hitGridChild(element: *Element, hit_grid: *HitGrid) void {
    hit_grid.fillRect(element.x, element.y, element.width, element.height, element.num);
}

fn requestDraw(element: *Element) void {
    if (element.context) |ctx| ctx.requestDraw();
}

fn onMouseEnter(element: *Element, _: vaxis.Mouse) void {
    const self: *Root = @ptrCast(@alignCast(element.userdata));
    self.bg_color = .{ .rgb = .{ 0x2a, 0x2a, 0x4e } };
    requestDraw(element);
}

fn onMouseLeave(element: *Element, _: vaxis.Mouse) void {
    const self: *Root = @ptrCast(@alignCast(element.userdata));
    self.bg_color = .{ .rgb = .{ 0x1a, 0x1a, 0x2e } };
    requestDraw(element);
}

fn onMouseDown(element: *Element, _: *EventContext, _: vaxis.Mouse) void {
    const self: *Root = @ptrCast(@alignCast(element.userdata));
    self.bg_color = .{ .rgb = .{ 0x0a, 0x0a, 0x1e } };
    requestDraw(element);
}

fn onMouseUp(element: *Element, _: *EventContext, _: vaxis.Mouse) void {
    const self: *Root = @ptrCast(@alignCast(element.userdata));
    self.bg_color = .{ .rgb = .{ 0x2a, 0x2a, 0x4e } };
    requestDraw(element);
}

fn onClick(element: *Element, _: *EventContext, _: vaxis.Mouse) void {
    const self: *Root = @ptrCast(@alignCast(element.userdata));
    self.bg_color = .{ .rgb = .{ 0x4a, 0x1a, 0x2e } };
    if (element.context) |ctx| ctx.setFocus(element);
    requestDraw(element);
}

fn onFocus(element: *Element) void {
    const self: *Root = @ptrCast(@alignCast(element.userdata));
    self.bg_color = .{ .rgb = .{ 0x2a, 0x4a, 0x2e } };
    requestDraw(element);
}

fn onBlur(element: *Element) void {
    const self: *Root = @ptrCast(@alignCast(element.userdata));
    self.bg_color = .{ .rgb = .{ 0x1a, 0x1a, 0x2e } };
    requestDraw(element);
}

fn onChildMouseEnter(element: *Element, _: vaxis.Mouse) void {
    const self: *Root = @ptrCast(@alignCast(element.userdata));
    self.child_bg_color = .{ .rgb = .{ 0x26, 0x31, 0x5e } };
    requestDraw(element);
}

fn onChildMouseLeave(element: *Element, _: vaxis.Mouse) void {
    const self: *Root = @ptrCast(@alignCast(element.userdata));
    self.child_bg_color = .{ .rgb = .{ 0x16, 0x21, 0x3e } };
    requestDraw(element);
}

fn onChildMouseDown(element: *Element, ctx: *EventContext, _: vaxis.Mouse) void {
    const self: *Root = @ptrCast(@alignCast(element.userdata));
    self.child_bg_color = .{ .rgb = .{ 0x06, 0x11, 0x2e } };
    requestDraw(element);
    ctx.stopPropagation();
}

fn onChildMouseUp(element: *Element, ctx: *EventContext, _: vaxis.Mouse) void {
    const self: *Root = @ptrCast(@alignCast(element.userdata));
    self.child_bg_color = .{ .rgb = .{ 0x26, 0x31, 0x5e } };
    requestDraw(element);
    ctx.stopPropagation();
}

fn onChildClick(element: *Element, ctx: *EventContext, _: vaxis.Mouse) void {
    const self: *Root = @ptrCast(@alignCast(element.userdata));
    self.child_bg_color = .{ .rgb = .{ 0x56, 0x21, 0x3e } };
    requestDraw(element);
    ctx.stopPropagation();
}

fn onChildWheel(element: *Element, ctx: *EventContext, mouse: vaxis.Mouse) void {
    const self: *Root = @ptrCast(@alignCast(element.userdata));
    switch (mouse.button) {
        .wheel_up => self.child_bg_color = .{ .rgb = .{ 0x16, 0x41, 0x3e } },
        .wheel_down => self.child_bg_color = .{ .rgb = .{ 0x16, 0x21, 0x5e } },
        else => {},
    }
    requestDraw(element);
    ctx.stopPropagation();
}
