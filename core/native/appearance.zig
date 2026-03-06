const std = @import("std");
const global = @import("../global.zig");
const MacAppearance = @import("./appearance/mac.zig");
const Allocator = std.mem.Allocator;

pub const Observer = MacAppearance.Observer;

const Appearance = @This();

pub fn isDark() bool {
    return MacAppearance.isDark();
}

test {
    const testing = std.testing;
    const alloc = testing.allocator;

    const observer = try Observer.create(alloc);
    defer observer.destroy();
}
