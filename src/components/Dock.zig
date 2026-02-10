const std = @import("std");
const vaxis = @import("vaxis");
const Allocator = std.mem.Allocator;

const lib = @import("../lib.zig");
const Element = lib.Element;
const Buffer = lib.Buffer;
const HitGrid = @import("../app/window/HitGrid.zig");
const global = @import("../global.zig");
const Settings = @import("../settings/mod.zig");

const Dock = @This();

pub const Side = enum {
    left,
    right,
    top,
    bottom,

    pub fn isHorizontal(self: Side) bool {
        return self == .top or self == .bottom;
    }

    pub fn isVertical(self: Side) bool {
        return self == .left or self == .right;
    }
};

const MIN_SIZE: u16 = 5;
const BORDER_SIZE: u16 = 1;

element: *Element,
side: Side,
size: u16,
settings: *Settings,

pub fn create(alloc: Allocator, side: Side, size: u16, visible: bool) !*Dock {
    const dock = try alloc.create(Dock);
    errdefer alloc.destroy(dock);

    const element = try alloc.create(Element);
    errdefer alloc.destroy(element);

    element.* = Element.init(alloc, .{
        .style = switch (side) {
            .left, .right => .{
                .width = .{ .point = @floatFromInt(size) },
                .height = .{ .percent = 100 },
                .flex_shrink = 0,
            },
            .top, .bottom => .{
                .width = .{ .percent = 100 },
                .height = .{ .point = @floatFromInt(size) },
                .flex_shrink = 0,
            },
        },
        .zIndex = 5,
        .userdata = dock,
        .hitFn = hit,
        .drawFn = draw,
    });

    if (visible) {
        element.show();
    } else {
        element.hide();
    }

    try element.addEventListener(.drag, onDrag);
    try element.addEventListener(.drag_end, onBarDragEnd);
    try element.addEventListener(.mouse_over, mouseOver);
    try element.addEventListener(.mouse_out, mouseOut);

    dock.* = .{
        .element = element,
        .side = side,
        .size = size,
        .settings = global.settings,
    };

    return dock;
}

pub fn destroy(self: *Dock, alloc: Allocator) void {
    if (!self.element.removed) {
        self.element.remove();
    }
    self.element.deinit();
    alloc.destroy(self.element);
    alloc.destroy(self);
}

pub fn toggleHidden(self: *Dock) void {
    if (self.element.visible) {
        self.element.hide();
    } else {
        self.element.show();
    }
}

fn hit(element: *Element, hit_grid: *HitGrid) void {
    const self: *Dock = @ptrCast(@alignCast(element.userdata));
    const layout = element.layout;

    switch (self.side) {
        .left => {
            hit_grid.fillRect(layout.left + layout.width -| BORDER_SIZE, layout.top -| 1, BORDER_SIZE + 1, layout.height, element.num);
        },
        .right => {
            hit_grid.fillRect(layout.left, layout.top, BORDER_SIZE, layout.height, element.num);
        },
        .top => {
            hit_grid.fillRect(layout.left, layout.top + layout.height -| BORDER_SIZE, layout.width, BORDER_SIZE, element.num);
        },
        .bottom => {
            hit_grid.fillRect(layout.left, layout.top, layout.width, BORDER_SIZE, element.num);
        },
    }
}

fn draw(element: *Element, buffer: *Buffer) void {
    const self: *Dock = @ptrCast(@alignCast(element.userdata));
    const layout = element.layout;
    const theme = global.settings.theme;

    element.fill(buffer, .{
        .style = .{ .bg = theme.bg, .fg = theme.fg },
    });

    buffer.fillRect(layout.left, layout.top -| 1, layout.width, 1, .{ .style = .{
        .bg = theme.bg,
    } });

    switch (self.side) {
        .left => {
            const char = "▕";

            const col = layout.left + layout.width -| BORDER_SIZE;
            var row: u16 = 0;
            while (row <= layout.height) : (row += 1) {
                if (row == 0) {
                    const alpha: u8 = if (element.hovered or element.dragging) 160 else 80;
                    buffer.writeCell(col, layout.top -| 1 + row, .{
                        .char = .{ .grapheme = "▄" },
                        .style = .{ .fg = .{ .rgba = .{ 40, 113, 180, alpha } }, .bg = theme.bg },
                    });

                    continue;
                }
                buffer.writeCell(col, layout.top -| 1 + row, .{
                    .char = .{ .grapheme = char },
                    .style = .{ .fg = self.settings.theme.border, .bg = theme.bg },
                });
            }
        },
        .right => {
            const col = layout.left;
            var row: u16 = 0;
            while (row < layout.height) : (row += 1) {
                buffer.writeCell(col, layout.top + row, .{
                    .char = .{ .grapheme = "│" },
                    .style = .{ .fg = self.settings.theme.border },
                });
            }
        },
        .top => {
            const row = layout.top + layout.height -| BORDER_SIZE;
            var col: u16 = 0;
            while (col < layout.width) : (col += 1) {
                buffer.writeCell(layout.left + col, row, .{
                    .char = .{ .grapheme = "─" },
                    .style = .{ .fg = self.settings.theme.border },
                });
            }
        },
        .bottom => {
            const row = layout.top;
            var col: u16 = 0;
            while (col < layout.width) : (col += 1) {
                buffer.writeCell(layout.left + col, row, .{
                    .char = .{ .grapheme = "─" },
                    .style = .{ .fg = self.settings.theme.border },
                });
            }
        },
    }
}

fn mouseOver(element: *Element, data: Element.EventData) void {
    const ctx = data.mouse_over.ctx;
    if (ctx.phase == .at_target) {
        element.context.?.app.screen.mouse_shape = .pointer;
        element.context.?.requestDraw();
    }
}

fn mouseOut(element: *Element, _: Element.EventData) void {
    element.context.?.app.screen.mouse_shape = .default;
    element.context.?.requestDraw();
}

fn onDrag(element: *Element, data: Element.EventData) void {
    const evt_data = data.drag;
    if (evt_data.ctx.phase != .at_target) return;

    element.context.?.app.screen.mouse_shape = .pointer;

    const mouse = evt_data.mouse;
    const self: *Dock = @ptrCast(@alignCast(element.userdata));

    const parent = element.parent orelse return;
    const parent_layout = parent.layout;
    const layout = element.layout;

    const new_size: u16 = switch (self.side) {
        .left => blk: {
            const mouse_x = mouse.col;
            const dock_left = layout.left;
            if (mouse_x < dock_left) break :blk MIN_SIZE;
            break :blk @intCast(@min(parent_layout.width -| MIN_SIZE, mouse_x -| dock_left));
        },
        .right => blk: {
            const mouse_x = mouse.col;
            const dock_right = layout.left + layout.width;
            if (mouse_x > dock_right) break :blk MIN_SIZE;
            break :blk @intCast(@min(parent_layout.width -| MIN_SIZE, dock_right -| mouse_x));
        },
        .top => blk: {
            const mouse_y = mouse.row;
            const dock_top = layout.top;
            if (mouse_y < dock_top) break :blk MIN_SIZE;
            break :blk @intCast(@min(parent_layout.height -| MIN_SIZE, mouse_y -| dock_top));
        },
        .bottom => blk: {
            const mouse_y = mouse.row;
            const dock_bottom = layout.top + layout.height;
            if (mouse_y > dock_bottom) break :blk MIN_SIZE;
            break :blk @intCast(@min(parent_layout.height -| MIN_SIZE, dock_bottom -| mouse_y));
        },
    };

    if (new_size < MIN_SIZE) return;

    self.size = new_size;
    self.applySize();

    element.context.?.requestDraw();
}

pub fn setSize(self: *Dock, size: u16) void {
    self.size = @max(MIN_SIZE, size);
    self.applySize();
}

fn applySize(self: *Dock) void {
    switch (self.side) {
        .left, .right => {
            self.element.style.width = .{ .point = @floatFromInt(self.size) };
            self.element.node.setWidth(.{ .point = @floatFromInt(self.size) });
        },
        .top, .bottom => {
            self.element.style.height = .{ .point = @floatFromInt(self.size) };
            self.element.node.setHeight(.{ .point = @floatFromInt(self.size) });
        },
    }
}

fn onBarDragEnd(element: *Element, _: Element.EventData) void {
    element.context.?.app.screen.mouse_shape = .default;

    if (element.context) |ctx| {
        ctx.requestDraw();
    }
}
