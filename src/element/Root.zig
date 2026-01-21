pub const Root = @This();

const Element = @import("Element.zig");
const Timer = @import("Timer.zig");
const AppContext = Element.AppContext;
const std = @import("std");
const vaxis = @import("vaxis");

const Allocator = std.mem.Allocator;

const Buffer = @import("../Buffer.zig");

const Direction = enum { up, down };

element: Element,

pub fn create(alloc: std.mem.Allocator) !*Root {
    const self = try alloc.create(Root);
    self.* = .{
        .element = Element.init(alloc, .{
            .id = "__root__",
            .userdata = self,
            .drawFn = draw,
        }),
    };
    return self;
}

pub fn destroy(self: *Root, alloc: Allocator) void {
    self.element.remove();

    alloc.destroy(self);
}

fn draw(element: *Element, buffer: *Buffer) void {
    _ = element;
    buffer.clear();
}
