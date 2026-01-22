const std = @import("std");
const builtin = @import("builtin");

pub const xev = @import("xev").Dynamic;

pub var counter: std.atomic.Value(u64) = .init(0);
