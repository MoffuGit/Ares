const std = @import("std");
const process = std.process;
const Io = std.Io;
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const rgfw = @import("rgfw");

const log = std.log.scoped(.global);

pub var state: GlobalState = .{};

const GlobalState = struct {
    const Self = @This();

    cpu_count: usize = 2,

    pub fn init(self: *Self) !void {
        const cpu_count = try std.Thread.getCpuCount();

        if (!builtin.is_test) {
            try rgfw.init("Odyssey", 0);
        }

        log.info("odyssey zig version={}", .{builtin.zig_version});
        log.info("odyssey build optimize={}", .{builtin.mode});

        self.* = .{
            .cpu_count = cpu_count,
        };
    }

    pub fn deinit(_: *Self) void {
        if (!builtin.is_test) {
            rgfw.deinit();
        }
    }
};
