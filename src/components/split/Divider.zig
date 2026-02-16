const std = @import("std");
const Allocator = std.mem.Allocator;
const vaxis = @import("vaxis");

const EventContext = @import("../events/EventContext.zig");
const Element = @import("../element/mod.zig").Element;
const Style = @import("../element/mod.zig").Style;
const Buffer = @import("../Buffer.zig");
const HitGrid = @import("../HitGrid.zig");
const split = @import("mod.zig");
const Direction = split.Direction;
const Sizing = split.Sizing;
const Node = split.Node;

const Divider = @This();

direction: Direction,
left: *Node,
right: *Node,
element: *Element,
dragging: bool,

pub fn create(alloc: Allocator, direction: Direction, left: *Node, right: *Node) !*Divider {
    const divider = try alloc.create(Divider);

    const element = try alloc.create(Element);
    element.* = Element.init(alloc, .{
        .style = switch (direction) {
            .horizontal => .{
                .height = .{ .point = 1 },
                .width = .{ .percent = 100 },
                .flex_shrink = 0,
            },
            .vertical => .{
                .width = .{ .point = 1 },
                .height = .{ .percent = 100 },
                .flex_shrink = 0,
            },
        },
        .zIndex = 10,
        .userdata = divider,
        .hitFn = Element.hitSelf,
        .drawFn = draw,
    });
    try element.addEventListener(.drag, Divider, divider, onDrag);
    try element.addEventListener(.mouse_enter, Divider, divider, mouseEnter);
    try element.addEventListener(.mouse_leave, Divider, divider, mouseLeave);

    divider.* = .{
        .direction = direction,
        .left = left,
        .right = right,
        .element = element,
        .dragging = false,
    };
    return divider;
}

fn draw(element: *Element, buffer: *Buffer) void {
    const self: *Divider = @ptrCast(@alignCast(element.userdata));
    const color: vaxis.Color = if (element.hovered or element.dragging)
        .{ .rgb = .{ 100, 100, 255 } }
    else
        .{ .rgb = .{ 80, 80, 80 } };

    const layout = element.layout;

    switch (self.direction) {
        .vertical => {
            const col = layout.left;
            const top = if (layout.top > 0) layout.top - 1 else 0;
            const height = if (layout.top > 0) layout.height + 1 else layout.height;
            var row: u16 = 0;
            while (row <= height) : (row += 1) {
                const y = top + row;
                const pos: Position = if (row == 0) .start else if (row == height) .end else .middle;
                const char = getVerticalChar(buffer, col, y, pos);
                const cell = vaxis.Cell{
                    .char = .{ .grapheme = char },
                    .style = .{ .fg = color },
                };
                buffer.writeCell(col, y, cell);
            }
        },
        .horizontal => {
            const row = layout.top;
            const left = if (layout.left > 0) layout.left - 1 else 0;
            const width = if (layout.left > 0) layout.width + 1 else layout.width;
            var col: u16 = 0;
            while (col <= width) : (col += 1) {
                const x = left + col;
                const pos: Position = if (col == 0) .start else if (col == width) .end else .middle;
                const char = getHorizontalChar(buffer, x, row, pos);
                const cell = vaxis.Cell{
                    .char = .{
                        .grapheme = char,
                    },
                    .style = .{ .fg = color },
                };
                buffer.writeCell(x, row, cell);
            }
        },
    }
}

const Position = enum { start, middle, end };

fn getVerticalChar(buffer: *Buffer, col: u16, row: u16, pos: Position) []const u8 {
    if (buffer.readCell(col, row)) |existing| {
        if (existing.char.grapheme.len > 0) {
            const g = existing.char.grapheme;
            if (std.mem.eql(u8, g, "─")) {
                return switch (pos) {
                    .start => "┬",
                    .end => "┴",
                    .middle => {
                        const left = if (buffer.readCell(col - 1, row)) |l| std.mem.eql(u8, l.char.grapheme, "─") else false;
                        const right = if (buffer.readCell(col + 1, row)) |r| std.mem.eql(u8, r.char.grapheme, "─") else false;
                        if (left and right) {
                            return "┼";
                        }

                        if (left) {
                            return "┤";
                        }

                        return "├";
                    },
                };
            }
            if (std.mem.eql(u8, g, "┴") or std.mem.eql(u8, g, "┬")) {
                return "┼";
            }
        }
    }
    return "│";
}

fn getHorizontalChar(buffer: *Buffer, col: u16, row: u16, pos: Position) []const u8 {
    if (buffer.readCell(col, row)) |existing| {
        if (existing.char.grapheme.len > 0) {
            const g = existing.char.grapheme;
            if (std.mem.eql(u8, g, "│")) {
                return switch (pos) {
                    .start => "├",
                    .end => "┤",
                    .middle => {
                        const left = if (buffer.readCell(col, row + 1)) |l| std.mem.eql(u8, l.char.grapheme, "│") else false;
                        const right = if (buffer.readCell(col, row - 1)) |r| std.mem.eql(u8, r.char.grapheme, "│") else false;
                        if (left and right) {
                            return "┼";
                        }

                        if (left) {
                            return "┬";
                        }

                        return "┴";
                    },
                };
            }
            if (std.mem.eql(u8, g, "┤") or std.mem.eql(u8, g, "├")) {
                return "┼";
            }
        }
    }
    return "─";
}

pub fn destroy(self: *Divider, alloc: Allocator) void {
    self.element.remove();
    self.element.deinit();
    alloc.destroy(self.element);
    alloc.destroy(self);
}

pub fn mouseEnter(_: *Divider, data: Element.EventData) void {
    const element = data.mouse_enter.element;
    element.context.?.window.screen.mouse_shape = .pointer;
    element.context.?.requestDraw();
}

pub fn mouseLeave(_: *Divider, data: Element.EventData) void {
    const element = data.mouse_leave.element;
    element.context.?.window.screen.mouse_shape = .default;
    element.context.?.requestDraw();
}

pub fn onDrag(self: *Divider, data: Element.EventData) void {
    const element = data.drag.element;
    const mouse = data.drag.mouse;

    const parent = element.parent orelse return;
    const parent_layout = parent.layout;

    const delta: f32 = switch (self.direction) {
        .vertical => blk: {
            const parent_width: f32 = @floatFromInt(parent_layout.width);
            if (parent_width == 0) break :blk 0;
            const mouse_x: f32 = @floatFromInt(mouse.col);
            const left_start: f32 = @floatFromInt(self.left.element.layout.left);
            const left_end: f32 = left_start + @as(f32, @floatFromInt(self.left.element.layout.width));
            break :blk (mouse_x - left_end) / parent_width;
        },
        .horizontal => blk: {
            const parent_height: f32 = @floatFromInt(parent_layout.height);
            if (parent_height == 0) break :blk 0;
            const mouse_y: f32 = @floatFromInt(mouse.row);
            const left_start: f32 = @floatFromInt(self.left.element.layout.top);
            const left_end: f32 = left_start + @as(f32, @floatFromInt(self.left.element.layout.height));
            break :blk (mouse_y - left_end) / parent_height;
        },
    };

    const total_ratio = self.left.ratio + self.right.ratio;
    const delta_ratio = delta * total_ratio;

    const new_left = @max(0.05, self.left.ratio + delta_ratio);
    const new_right = @max(0.05, self.right.ratio - delta_ratio);

    if (new_left < 0.05 or new_right < 0.05) return;

    const new_left_size: f32 = switch (self.direction) {
        .vertical => blk: {
            const current: f32 = @floatFromInt(self.left.element.layout.width);
            const delta_px = delta * @as(f32, @floatFromInt(parent_layout.width));
            break :blk current + delta_px;
        },
        .horizontal => blk: {
            const current: f32 = @floatFromInt(self.left.element.layout.height);
            const delta_px = delta * @as(f32, @floatFromInt(parent_layout.height));
            break :blk current + delta_px;
        },
    };
    const new_right_size: f32 = switch (self.direction) {
        .vertical => blk: {
            const current: f32 = @floatFromInt(self.right.element.layout.width);
            const delta_px = delta * @as(f32, @floatFromInt(parent_layout.width));
            break :blk current - delta_px;
        },
        .horizontal => blk: {
            const current: f32 = @floatFromInt(self.right.element.layout.height);
            const delta_px = delta * @as(f32, @floatFromInt(parent_layout.height));
            break :blk current - delta_px;
        },
    };

    const left_min: f32 = @floatFromInt(self.left.minSize(self.direction));
    const right_min: f32 = @floatFromInt(self.right.minSize(self.direction));
    if (new_left_size < left_min or new_right_size < right_min) return;

    self.left.ratio = new_left;
    self.right.ratio = new_right;

    self.left.sizing = .fixed;
    self.right.sizing = .fixed;

    self.left.applyRatio();
    self.right.applyRatio();

    element.context.?.requestDraw();
}

test "create divider" {
    const alloc = std.testing.allocator;

    const left = try Node.createView(alloc, 1);
    defer left.destroy(alloc);

    const right = try Node.createView(alloc, 2);
    defer right.destroy(alloc);

    const divider = try Divider.create(alloc, .vertical, left, right);
    defer divider.destroy(alloc);

    try std.testing.expectEqual(Direction.vertical, divider.direction);
    try std.testing.expectEqual(left, divider.left);
    try std.testing.expectEqual(right, divider.right);
    try std.testing.expect(!divider.dragging);
}
