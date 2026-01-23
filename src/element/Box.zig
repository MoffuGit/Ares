pub const Box = @This();

const std = @import("std");
const vaxis = @import("vaxis");
const Element = @import("mod.zig").Element;
const Style = @import("mod.zig").Style;
const Buffer = @import("../Buffer.zig");

const Allocator = std.mem.Allocator;

pub const Options = struct {
    id: ?[]const u8 = null,
    style: Style = .{},
    background: ?vaxis.Cell.Color = null,
};

element: Element,
background: ?vaxis.Cell.Color = null,

pub fn create(alloc: Allocator, opts: Options) !*Box {
    const self = try alloc.create(Box);
    self.* = .{
        .element = Element.init(alloc, .{
            .id = opts.id,
            .userdata = self,
            .drawFn = draw,
            .style = opts.style,
        }),
        .background = opts.background,
    };
    return self;
}

pub fn destroy(self: *Box, alloc: Allocator) void {
    self.element.deinit();
    alloc.destroy(self);
}

fn draw(element: *Element, buffer: *Buffer) void {
    const self: *Box = @ptrCast(@alignCast(element.userdata));
    const bg = self.background orelse return;

    const x = element.layout.left;
    const y = element.layout.top;

    var row: u16 = 0;
    while (row < element.layout.height) : (row += 1) {
        var col: u16 = 0;
        while (col < element.layout.width) : (col += 1) {
            const px = x + col;
            const py = y + row;
            if (px < buffer.width and py < buffer.height) {
                buffer.writeCell(px, py, .{ .style = .{ .bg = bg } });
            }
        }
    }
}
