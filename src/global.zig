const std = @import("std");
const process = std.process;
const Io = std.Io;
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");

const log = std.log.scoped(.global);

pub var cpu_count: usize = 2;

pub fn init() !void {
    cpu_count = try std.Thread.getCpuCount();

    log.info("odyssey zig version={}", .{builtin.zig_version});
    log.info("odyssey build optimize={}", .{builtin.mode});
}

pub fn deinit() void {}
