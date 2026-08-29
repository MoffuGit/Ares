//LICENSE: [GHOSTTY]
const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub fn SwapChain(T: type, buf_count: comptime_int) type {
    return struct {
        io: Io,
        buffer: [buf_count]T,
        index: std.math.IntFittingRange(0, buf_count) = 0,
        semaphore: std.Io.Semaphore = .{ .permits = buf_count },

        pub fn init(self: *@This(), gpa: Allocator, io: Io) !void {
            self.* = .{
                .io = io,
                .buffer = undefined,
            };

            for (&self.buffer) |*frame| {
                try frame.init(gpa);
            }
        }

        pub fn deinit(self: *@This()) void {
            for (0..buf_count) |_| self.semaphore.waitUncancelable(self.io);
            for (&self.buffer) |*frame| frame.deinit();
        }

        pub fn nextFrame(self: *@This()) *T {
            self.semaphore.waitUncancelable(self.io);
            errdefer self.semaphore.post();
            self.index = (self.index + 1) % buf_count;
            return &self.buffer[self.index];
        }

        pub fn releaseFrame(self: *@This()) void {
            self.semaphore.post(self.io);
        }
    };
}
