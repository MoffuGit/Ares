const std = @import("std");
const datastruct = @import("datastruct/mod.zig");

const state = &@import("global.zig").state;

pub fn main() !void {
    try state.init();
    defer state.deinit();
}
