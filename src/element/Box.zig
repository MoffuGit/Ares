pub const Box = @This();

const std = @import("std");
const vaxis = @import("vaxis");
const Element = @import("Element.zig");
const Animation = Element.Animation;
const Buffer = @import("../Buffer.zig");

const Allocator = std.mem.Allocator;

const Options = struct {
    id: []const u8,
    x: u16 = 0,
    y: u16 = 0,
    width: u16 = 0,
    height: u16 = 0,
};

element: Element,

pub fn create(alloc: Allocator, opts: Options) !*Box {
    const self = try alloc.create(Box);
    self.* = .{
        .element = Element.init(alloc, .{
            .id = opts.id,
            .userdata = self,
            .drawFn = draw,
            .height = opts.height,
            .width = opts.width,
            .x = opts.x,
            .y = opts.y,
        }),
    };
    return self;
}

pub fn destroy(self: *Box, alloc: Allocator) void {
    self.element.remove();

    alloc.destroy(self);
}

fn draw(element: *Element, buffer: *Buffer) void {
    _ = element.userdata;
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
