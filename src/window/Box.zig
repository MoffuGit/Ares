pub const Box = @This();

const std = @import("std");
const vaxis = @import("vaxis");
const Element = @import("Element.zig");
const Animation = Element.Animation;
const Buffer = @import("../Buffer.zig");

const Options = struct {
    x: u16 = 0,
    y: u16 = 0,
    width: u16 = 0,
    height: u16 = 0,
};

element: Element,

pub fn create(alloc: std.mem.Allocator, opts: Options) !*Box {
    const self = try alloc.create(Box);
    self.* = .{
        .element = try Element.init(alloc, .{
            .drawFn = draw,
            .destroyFn = destroy,
            .height = opts.height,
            .width = opts.width,
            .x = opts.x,
            .y = opts.y,
        }),
    };
    return self;
}

fn destroy(element: *Element, alloc: std.mem.Allocator) void {
    const self: *Box = @fieldParentPtr("element", element);
    alloc.destroy(self);
}

fn draw(element: *Element, buffer: *Buffer) void {
    const x: u16 = element.x;
    const y: u16 = element.y;

    var row: u16 = 0;
    while (row < element.height) : (row += 1) {
        var col: u16 = 0;
        while (col < element.width) : (col += 1) {
            const px = x + col;
            const py = y + row;
            if (px < buffer.width and py < buffer.height) {
                buffer.writeCell(px, py, .{ .style = .{ .bg = .{ .rgba = .{ 255, 0, 0, 255 } } } });
            }
        }
    }
}
