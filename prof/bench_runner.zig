const std = @import("std");
const builtin = @import("builtin");

pub fn main() !void {
    for (builtin.test_functions) |test_fn| {
        std.testing.allocator_instance = .{};
        defer _ = std.testing.allocator_instance.deinit();

        std.testing.io_instance = .init(std.testing.allocator, .{});
        defer std.testing.io_instance.deinit();

        std.testing.log_level = .debug;
        try test_fn.func();
    }
}
