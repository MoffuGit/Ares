const std = @import("std");
const global = @import("../global.zig");
const MacAppearance = @import("./appearance/mac.zig");
const Allocator = std.mem.Allocator;

const Appearance = @This();

pub fn isDark() bool {
    return MacAppearance.isDark();
}
