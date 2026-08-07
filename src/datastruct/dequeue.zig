//SOURCE: https://github.com/dmtrKovalenko/zlob
//LICENSE: [ZLOB]

const std = @import("std");
const Io = std.Io;
const atomic = std.atomic;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const queue = @import("queue.zig");

pub fn Dequeue(T: type) type {
    return struct {
        const Self = @This();

        const Queue = struct {
            mutex: Io.Mutex = .init,
            queue: queue.Queue(T) = .{},
            approx_len: atomic.Value(usize) = .init(0),
        };

        queues: []Queue,
        wait_mutex: Io.Mutex,
        cond: Io.Condition,
        queued: atomic.Value(usize),
        outstanding: atomic.Value(usize),
        closed: atomic.Value(bool),

        pub fn init(self: *Self, alloc: Allocator, workers: u32) !void {
            assert(workers > 0);
            self.* = .{
                .closed = .init(false),
                .cond = .init,
                .outstanding = .init(0),
                .queued = .init(0),
                .queues = undefined,
                .wait_mutex = .init,
            };

            self.queues = try alloc.alloc(Queue, workers);
            for (self.queues) |*local| local.* = .{};
        }

        pub fn deinit(self: *Self, alloc: Allocator) void {
            alloc.free(self.queues);
        }

        pub fn push(self: *Self, io: Io, worker_id: u32, job: *T) !void {
            if (self.closed.load(.acquire)) return error.Closed;

            const local = &self.queues[self.localIndex(worker_id)];

            var queued_before: usize = 0;

            {
                try local.mutex.lock(io);
                defer local.mutex.unlock(io);

                local.queue.push(job);

                _ = local.approx_len.fetchAdd(1, .release);
                _ = self.outstanding.fetchAdd(1, .release);

                queued_before = self.queued.fetchAdd(1, .release);
            }

            if (queued_before < self.queues.len) try self.wakeOne(io);
        }

        pub fn pop(self: *Self, io: Io, worker_id: u32) !*T {
            const home = self.localIndex(worker_id);
            while (true) {
                if (self.popFrom(io, home)) |job| return job;
                if (self.steal(io, home)) |job| return job;
                if (self.closed.load(.acquire)) return error.Closed;

                try self.wait_mutex.lock(io);
                defer self.wait_mutex.unlock(io);

                while (self.queued.load(.acquire) == 0 and !self.closed.load(.acquire)) {
                    try self.cond.wait(io, &self.wait_mutex);
                }
            }
        }

        pub fn close(self: *Self, io: Io) !void {
            self.closed.store(true, .release);
            try self.wakeAll(io);
        }

        pub fn taskDone(self: *Self) usize {
            return self.outstanding.fetchSub(1, .release);
        }

        pub fn wakeAll(self: *Self, io: Io) !void {
            try self.wait_mutex.lock(io);
            defer self.wait_mutex.unlock(io);
            self.cond.broadcast(io);
        }

        fn wakeOne(self: *Self, io: Io) !void {
            try self.wait_mutex.lock(io);
            defer self.wait_mutex.unlock(io);
            self.cond.signal(io);
        }

        fn localIndex(self: *Self, worker_id: u32) usize {
            return @as(usize, @intCast(worker_id)) % self.queues.len;
        }

        fn popFrom(self: *Self, io: Io, index: usize) ?*T {
            const local = &self.queues[index];
            if (local.approx_len.load(.acquire) == 0) return null;

            local.mutex.lock(io) catch return null;
            defer local.mutex.unlock(io);

            const job = local.queue.pop() orelse return null;
            _ = local.approx_len.fetchSub(1, .release);
            _ = self.queued.fetchSub(1, .acq_rel);
            return job;
        }

        fn steal(self: *Self, io: Io, home: usize) ?*T {
            var offset: usize = 1;
            while (offset < self.queues.len) : (offset += 1) {
                const index = (home + offset) % self.queues.len;
                if (self.queues[index].approx_len.load(.acquire) == 0) continue;
                if (self.popFrom(io, index)) |job| return job;
            }
            return null;
        }

        pub const Iterator = struct {
            channel: *Self,
            index: u32,

            pub fn next(self: *Iterator) ?*T {
                while (true) {
                    if (self.index >= self.channel.queues.len) return null;

                    const slot = &self.channel.queues[self.index];

                    if (slot.queue.pop()) |value| {
                        return value;
                    } else {
                        self.index += 1;
                    }
                }
            }
        };

        pub fn iterator(self: *Self) Iterator {
            return .{
                .channel = self,
                .index = 0,
            };
        }
    };
}
