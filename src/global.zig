const std = @import("std");
const process = std.process;
const Io = std.Io;
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");

const log = std.log.scoped(.global);

pub var state: GlobalState = .{};

const use_safe_allocator = switch (builtin.mode) {
    .Debug, .ReleaseSafe => true,
    .ReleaseFast, .ReleaseSmall => !builtin.link_libc and builtin.single_threaded, // Also not ideal.
};

var safe_allocator: std.heap.DebugAllocator(.{}) = .init;

const GlobalState = struct {
    const Self = @This();

    gpa: Allocator = undefined,
    threaded: Io.Threaded = undefined,
    cpu_count: usize = 2,

    pub fn init(self: *Self, args: process.Args.Vector, environ: process.Environ.Block) !void {
        const gpa = if (use_safe_allocator)
            safe_allocator.allocator()
        else if (builtin.link_libc)
            std.heap.c_allocator
        else
            comptime unreachable;

        const cpu_count = try std.Thread.getCpuCount();

        const threaded: std.Io.Threaded = .init(gpa, .{
            .argv0 = .init(.{ .vector = args }),
            .environ = .{ .block = environ },
        });

        log.info("odyssey zig version={}", .{builtin.zig_version});
        log.info("odyssey build optimize={}", .{builtin.mode});

        self.* = .{
            .gpa = gpa,
            .threaded = threaded,
            .cpu_count = cpu_count,
        };
    }

    pub fn deinit(self: *Self) void {
        self.threaded.deinit();
        if (use_safe_allocator) {
            _ = safe_allocator.deinit(); // Leaks do not affect return code.
        }
    }
};
