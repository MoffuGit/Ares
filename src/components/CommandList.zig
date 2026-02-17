const std = @import("std");
const vaxis = @import("vaxis");
const lib = @import("../lib.zig");

const Element = lib.Element;
const Box = Element.Box;
const Allocator = std.mem.Allocator;

const CommandList = @This();

alloc: Allocator,
container: *Box,
item: *Box,

pub fn create(alloc: Allocator) !*CommandList {
    const self = try alloc.create(CommandList);
    errdefer alloc.destroy(self);

    const container = try Box.init(alloc, .{
        .style = .{
            .width = .{ .percent = 100 },
            .flex_grow = 1,
        },
    });
    errdefer container.deinit(alloc);

    const item = try Box.init(alloc, .{
        .style = .{
            .width = .{ .percent = 100 },
            .height = .{ .percent = 100 },
            .border = .{ .top = 1 },
        },
        .border = .{ .kind = .single },
    });
    errdefer item.deinit(alloc);

    try container.element.childs(.{item});

    self.* = .{
        .alloc = alloc,
        .container = container,
        .item = item,
    };

    return self;
}

pub fn destroy(self: *CommandList) void {
    self.item.deinit(self.alloc);
    self.container.deinit(self.alloc);
    self.alloc.destroy(self);
}
