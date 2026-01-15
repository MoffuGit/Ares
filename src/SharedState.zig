const std = @import("std");
const vaxis = @import("vaxis");
const Allocator = std.mem.Allocator;

pub const SharedState = @This();

mutex: std.Thread.Mutex = .{},

screen: vaxis.Screen,
render: bool = false,

pub fn init(alloc: Allocator, size: vaxis.Winsize) !SharedState {
    return .{
        .screen = try .init(alloc, size),
    };
}

pub fn deinit(self: *SharedState, alloc: Allocator) void {
    self.screen.deinit(alloc);
}
