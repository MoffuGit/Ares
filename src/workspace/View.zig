const std = @import("std");
const lib = @import("../lib.zig");
const Element = lib.Element;
const Buffer = lib.Buffer;

const View = @This();

root: *Element,
center: *Element,
bottom_bar: *Element,

pub fn create(alloc: std.mem.Allocator) !*View {
    const self = try alloc.create(View);
    errdefer alloc.destroy(self);

    const root = try alloc.create(Element);
    errdefer alloc.destroy(root);

    const center = try alloc.create(Element);
    errdefer alloc.destroy(center);

    const bottom_bar = try alloc.create(Element);
    errdefer alloc.destroy(bottom_bar);

    root.* = Element.init(alloc, .{
        .id = "workspace-root",
        .style = .{
            .width = .{ .percent = 100 },
            .height = .{ .percent = 100 },
            .flex_direction = .column,
        },
    });

    center.* = Element.init(alloc, .{
        .id = "center",
        .drawFn = drawCenter,
        .style = .{
            .width = .{ .percent = 100 },
            .flex_grow = 1,
        },
    });

    bottom_bar.* = Element.init(alloc, .{
        .id = "bottom-bar",
        .drawFn = drawBottomBar,
        .style = .{
            .width = .{ .percent = 100 },
            .height = .{ .point = 1 },
            .flex_shrink = 0,
        },
    });

    try root.addChild(center);
    try root.addChild(bottom_bar);

    self.* = .{
        .root = root,
        .center = center,
        .bottom_bar = bottom_bar,
    };

    return self;
}

pub fn destroy(self: *View, alloc: std.mem.Allocator) void {
    self.bottom_bar.deinit();
    alloc.destroy(self.bottom_bar);

    self.center.deinit();
    alloc.destroy(self.center);

    self.root.deinit();
    alloc.destroy(self.root);

    alloc.destroy(self);
}

pub fn addTopBar(self: *View, top_bar: *Element) !void {
    try self.root.insertChild(top_bar, 0);
}

pub fn getElement(self: *View) *Element {
    return self.root;
}

fn drawCenter(element: *Element, buffer: *Buffer) void {
    element.fill(buffer, .{ .style = .{ .bg = .{ .rgb = .{ 255, 0, 0 } } } });
}

fn drawBottomBar(element: *Element, buffer: *Buffer) void {
    element.fill(buffer, .{ .style = .{ .bg = .{ .rgb = .{ 0, 0, 255 } } } });
}
