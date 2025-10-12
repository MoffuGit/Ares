const std = @import("std");

var counter: i32 = 0;

export fn zig_increment_counter() void {
    counter += 1;
    std.debug.print("Zig: Counter incremented to {}\n", .{counter});
}

export fn zig_decrement_counter() void {
    counter -= 1;
    std.debug.print("Zig: Counter decremented to {}\n", .{counter});
}

export fn zig_get_counter() i32 {
    std.debug.print("Zig: Counter requested, returning {}\n", .{counter});
    return counter;
}

export fn zig_init_counter() void {
    counter = 0;
    std.debug.print("Zig: Counter initialized to {}\n", .{counter});
}

export fn zig_deinit_counter() void {
    std.debug.print("Zig: Counter deinitialized.\n", .{});
}
