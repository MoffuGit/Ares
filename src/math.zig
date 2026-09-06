const std = @import("std");
const debug = std.debug;
const assert = debug.assert;

///[min, max) range
pub fn Rng(T: type) type {
    return struct {
        min: T,
        max: T,

        pub inline fn new(min: T, max: T) @This() {
            return .{ .min = min, .max = max };
        }

        pub inline fn contains(self: @This(), value: T) bool {
            return value >= self.min and value < self.max;
        }

        pub inline fn dim(self: @This()) T {
            return if (self.max > self.min) self.max - self.min else 0;
        }

        pub inline fn empty(self: @This()) bool {
            return self.min >= self.max;
        }

        pub inline fn intersect(a: @This(), b: @This()) @This() {
            return .new(@max(a.min, b.min), @min(a.max, b.max));
        }
    };
}

pub const Rngu64 = Rng(u64);

pub const Rngu64Node = struct {
    range: Rngu64,
    next: ?*Rngu64Node = null,
};
