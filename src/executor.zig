const std = @import("std");
const heap = std.heap;
const Allocator = std.mem.Allocator;
const Io = std.Io;

const Loop = @import("loop.zig");
const Completion = Loop.Completion;

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

const Worker = struct {
    loop: Loop,

    pub fn init(self: *Worker) !void {
        try self.loop.init();
    }

    pub fn run(self: *Worker) !void {
        self.loop.run(.until_done) catch {};
    }

    pub fn deinit(self: *Worker, io: Io) void {
        self.loop.deinit(io);
    }
};

pub const BackgroundExecutor = struct {
    workers: []Worker,
    group: Io.Group,

    pub fn init(self: *BackgroundExecutor, gpa: Allocator, io: Io) !void {
        const cpu_count = try std.Thread.getCpuCount();

        const workers = try gpa.alloc(Worker, cpu_count);
        errdefer gpa.free(workers);

        self.* = .{
            .workers = workers,
            .group = .init,
        };

        for (self.workers) |*worker| {
            try worker.init();
            try self.group.concurrent(io, Worker.run, .{worker});
        }
    }

    pub fn deinit(self: *BackgroundExecutor, gpa: Allocator, io: Io) void {
        self.group.cancel(io);

        for (self.workers) |*worker| {
            worker.deinit(io);
        }

        gpa.free(self.workers);
    }
};
