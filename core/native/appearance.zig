const std = @import("std");
const MacAppearance = @import("./appearance/mac.zig");

const Appearance = @This();

pub fn get() bool {
    return MacAppearance.get();
}
