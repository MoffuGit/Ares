const std = @import("std");
const debug = std.debug;
const assert = debug.assert;

///[min, max) range
pub const Rngu64 = struct {
    min: u64,
    max: u64,

    pub fn new(min: u64, max: u64) Rngu64 {
        return .{ .min = min, .max = max };
    }

    pub inline fn contains(self: *const @This(), int: u64) bool {
        return int >= self.min and int < self.max;
    }

    pub inline fn dim(self: *const @This()) u64 {
        return if (self.max > self.min) self.max - self.min else 0;
    }

    pub inline fn empty(self: *const @This()) bool {
        return self.min >= self.max;
    }

    pub inline fn intersect(a: Rngu64, b: Rngu64) Rngu64 {
        return .new(@max(a.min, b.min), @min(a.max, b.max));
    }
};

pub const Rngu64Node = struct {
    range: Rngu64,
    next: ?*Rngu64Node = null,
};
