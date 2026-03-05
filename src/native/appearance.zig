const std = @import("std");
const MacAppearance = @import("./appearance/mac.zig");

const Appearance = @This();

pub fn get() bool {
    return MacAppearance.get();
}

test "get" {
    const testing = std.testing;
    const dark = Appearance.get();
    try testing.expect(dark);
}
