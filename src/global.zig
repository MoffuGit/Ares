const std = @import("std");
const process = std.process;
const Io = std.Io;
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const c = @import("c");

const log = std.log.scoped(.global);

pub var state: GlobalState = .{};

const GlobalState = struct {
    const Self = @This();

    cpu_count: usize = 2,

    pub fn init(self: *Self) !void {
        const cpu_count = try std.Thread.getCpuCount();

        if (!builtin.is_test) {
            const status = c.RGFW_init("Odyssey", 0);
            if (status != 0) return error.RGFWInitError;
        }

        log.info("odyssey zig version={}", .{builtin.zig_version});
        log.info("odyssey build optimize={}", .{builtin.mode});

        self.* = .{
            .cpu_count = cpu_count,
        };
    }

    pub fn deinit(_: *Self) void {
        if (!builtin.is_test) {
            c.RGFW_deinit();
        }
    }
};
