const std = @import("std");
const builtin = @import("builtin");
const process = std.process;

pub var state: GlobalState = undefined;

const use_safe_allocator = switch (builtin.mode) {
    .Debug, .ReleaseSafe => true,
    .ReleaseFast, .ReleaseSmall => !builtin.link_libc and builtin.single_threaded, // Also not ideal.
};

var safe_allocator: std.heap.DebugAllocator(.{}) = .init;

const GlobalState = struct {
    const Self = @This();

    gpa: std.mem.Allocator,
    threaded: std.Io.Threaded,

    pub fn init(self: *Self, args: process.Args.Vector, environ: process.Environ.Block) !void {
        const gpa = if (use_safe_allocator)
            safe_allocator.allocator()
        else if (builtin.link_libc)
            std.heap.c_allocator
        else
            comptime unreachable;

        const threaded: std.Io.Threaded = .init(gpa, .{
            .argv0 = .init(.{ .vector = args }),
            .environ = .{ .block = environ },
        });

        std.log.info("odyssey zig version={}", .{builtin.zig_version});
        std.log.info("odyssey build optimize={}", .{builtin.mode});

        self.* = .{
            .gpa = gpa,
            .threaded = threaded,
        };
    }

    pub fn deinit(self: *Self) void {
        if (use_safe_allocator) {
            _ = safe_allocator.deinit(); // Leaks do not affect return code.
        }
        self.threaded.deinit();
    }
};
