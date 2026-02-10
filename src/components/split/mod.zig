const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Tree = @import("Tree.zig");
pub const Node = @import("Node.zig");
pub const Divider = @import("Divider.zig");

pub const Direction = enum {
    horizontal,
    vertical,

    pub fn toFlexDirection(self: Direction) @import("../element/mod.zig").Style.FlexDirection {
        return switch (self) {
            .horizontal => .column,
            .vertical => .row,
        };
    }
};

pub const Sizing = enum {
    equal,
    fixed,
};

pub const MIN_WIDTH: u16 = 9;
pub const MIN_HEIGHT: u16 = 3;

test {
    std.testing.refAllDecls(@This());
}
