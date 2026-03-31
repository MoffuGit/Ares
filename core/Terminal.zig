const Terminal = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.terminal);

alloc: Allocator,
ptr: *anyopaque,

pub fn create(alloc: Allocator, layer_ptr: *anyopaque) !*Terminal {
    const self = try alloc.create(Terminal);
    errdefer alloc.destroy(self);

    self.* = .{
        .alloc = alloc,
        .ptr = layer_ptr,
    };

    return self;
}
pub fn destroy(self: *Terminal) void {
    self.alloc.destroy(self);
}
