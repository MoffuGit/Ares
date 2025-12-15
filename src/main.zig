const std = @import("std");
const datastruct = @import("datastruct/mod.zig");

pub fn main() !void {
    std.debug.print("Hello, World!\n", .{});
}

test {
    _ = datastruct;
}
