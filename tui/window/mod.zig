const std = @import("std");
const vaxis = @import("vaxis");
const yoga = @import("element/Node.zig").yoga;

pub const Element = @import("element/mod.zig");
pub const Mouse = @import("Mouse.zig");
const Buffer = @import("../Buffer.zig");
const Bus = @import("../Bus.zig");
const Screen = @import("../Screen.zig");
const HitGrid = @import("HitGrid.zig");
const Allocator = std.mem.Allocator;
const Elements = std.AutoHashMap(u64, *Element);
const Box = @import("element/Box.zig");

const Window = @This();

alloc: Allocator,

root: ?*Element = null,

size: vaxis.Winsize,
screen: *Screen,

focused_id: ?u64 = null,
hit_grid: HitGrid,
hovered_id: ?u64 = null,
pressed_id: ?u64 = null,
elements: Elements,

pub fn init(alloc: Allocator, screen: *Screen) !Window {
    const hit_grid = try HitGrid.init(alloc, 0, 0);

    return .{
        .screen = screen,
        .alloc = alloc,
        .size = .{ .cols = 0, .rows = 0, .x_pixel = 0, .y_pixel = 0 },
        .elements = Elements.init(alloc),
        .hit_grid = hit_grid,
    };
}

pub fn deinit(self: *Window) void {
    var it = self.elements.valueIterator();
    while (it.next()) |entry| {
        const elem = entry.*;
        switch (elem.kind) {
            .box => {
                const box: *Box = @ptrCast(@alignCast(elem.userdata orelse continue));
                box.deinit(self.alloc);
            },
            .raw => {
                elem.deinit();
                self.alloc.destroy(elem);
            },
        }
    }
    self.hit_grid.deinit();
    self.elements.deinit();
}

pub fn setRoot(self: *Window, elem: *Element) void {
    self.root = elem;
}

pub fn addElement(self: *Window, elem: *Element) !void {
    try self.elements.put(elem.num, elem);
}

pub fn removeElement(self: *Window, num: u64) void {
    _ = self.elements.remove(num);
    if (self.hovered_id) |id| {
        if (id == num) self.hovered_id = null;
    }
    if (self.pressed_id) |id| {
        if (id == num) self.pressed_id = null;
    }
    if (self.focused_id) |id| {
        if (id == num) self.focused_id = null;
    }
}

pub fn getElement(self: *Window, num: u64) ?*Element {
    return self.elements.get(num);
}

pub fn resize(self: *Window, size: vaxis.Winsize) void {
    if (self.size.rows == size.rows and self.size.cols == size.cols) return;
    self.size = size;
}

pub fn draw(self: *Window) !void {
    const root = self.root orelse return;

    self.calculateLayout();

    const screen = self.screen;
    const size = self.size;

    const hit_grid = &self.hit_grid;

    if (hit_grid.width != size.cols or hit_grid.height != size.rows) {
        try hit_grid.resize(size.cols, size.rows);
    }

    root.hit(&self.hit_grid);

    const buffer = try screen.nextBuffer();
    errdefer screen.releaseBuffer();

    if (buffer.width != size.cols or buffer.height != size.rows) {
        try screen.resizeBuffer(self.alloc, buffer, size);
    }

    buffer.clear();

    root.draw(buffer);
}

pub fn calculateLayout(self: *Window) void {
    const root = self.root orelse return;
    yoga.YGNodeCalculateLayout(root.node.yg_node, @floatFromInt(self.size.cols), @floatFromInt(self.size.rows), yoga.YGDirectionLTR);
    applyLayout(root, false);
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

pub fn tryHit(self: *Window, col: u16, row: u16) ?u64 {
    return self.hit_grid.get(col, row);
}

pub fn setFocus(self: *Window, id: ?u64) void {
    self.focused_id = id;
}

pub fn getFocusedId(self: *Window) ?u64 {
    return self.focused_id;
}

pub fn resolveMouseEvent(self: *Window, vaxis_mouse: vaxis.Mouse, bus: *Bus) void {
    const mouse = Mouse.fromVaxis(vaxis_mouse, self.size);
    const curr_id = self.tryHit(mouse.col, mouse.row);
    const prev_id = self.hovered_id;

    const mouse_data = Bus.MouseData{
        .col = mouse.col,
        .row = mouse.row,
        .button = @intFromEnum(mouse.button),
    };

    // hover changes
    if (curr_id != prev_id) {
        if (prev_id) |old| {
            bus.push(.mouse_leave, old, .{ .mouse = mouse_data });
        }
        if (curr_id) |new| {
            bus.push(.mouse_enter, new, .{ .mouse = mouse_data });
        }
        self.hovered_id = curr_id;
    }

    const target = curr_id orelse return;

    switch (mouse.type) {
        .press => {
            self.pressed_id = target;
            bus.push(.mouse_down, target, .{ .mouse = mouse_data });
        },
        .release => {
            bus.push(.mouse_up, target, .{ .mouse = mouse_data });
            if (self.pressed_id) |pressed| {
                if (pressed == target) {
                    bus.push(.click, target, .{ .mouse = mouse_data });
                }
            }
            self.pressed_id = null;
        },
        .motion, .drag => {
            bus.push(.mouse_move, target, .{ .mouse = mouse_data });
        },
    }

    const is_wheel = switch (mouse.button) {
        .wheel_up, .wheel_down, .wheel_left, .wheel_right => true,
        else => false,
    };

    if (is_wheel) {
        bus.push(.wheel, target, .{ .mouse = mouse_data });
    }
}

pub fn resolveKeyEvent(self: *Window, key: vaxis.Key, event_type: Bus.EventType, bus: *Bus) void {
    const root_id = if (self.root) |r| r.num else return;
    const target = self.focused_id orelse root_id;
    bus.push(event_type, target, .{ .key = Bus.KeyData.fromVaxis(key) });
}
