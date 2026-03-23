const SharedState = @This();

const std = @import("std");

mutex: std.Thread.Mutex = .{},
