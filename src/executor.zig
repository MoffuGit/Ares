const Loop = @import("loop.zig");
const std = @import("std");
const Io = std.Io;

pub const ForegroundExecutor = struct {
    loop: Loop,

    pub fn init(self: *ForegroundExecutor) !void {
        try self.loop.init();
    }

    pub fn run(self: *ForegroundExecutor) !void {
        try self.loop.run(.no_wait);
    }

    pub fn deinit(self: *ForegroundExecutor, io: Io) void {
        self.loop.deinit(io);
    }
};
