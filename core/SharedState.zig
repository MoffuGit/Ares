const SharedState = @This();

const std = @import("std");
const sizepkg = @import("size.zig");
const Allocator = std.mem.Allocator;
const Screen = @import("Screen.zig");

mutex: std.Thread.Mutex = .{},
screen: Screen,

pub fn init(alloc: Allocator, size: sizepkg.Size) !SharedState {
    return .{
        .screen = try Screen.init(alloc, size),
    };
}

pub fn deinit(self: *SharedState) void {
    self.screen.deinit();
}
