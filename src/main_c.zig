const std = @import("std");
const state = &@import("global.zig").state;
const embedded = @import("apprt/embedded.zig");

comptime {
    _ = embedded.CAPI;
}

pub export fn ares_init(argc: usize, argv: [*][*:0]u8) c_int {
    std.os.argv = argv[0..argc];
    state.init() catch |err| {
        std.log.err("failed to initialize ghostty error={}", .{err});
        return 1;
    };

    return 0;
}
