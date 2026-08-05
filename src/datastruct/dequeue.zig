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

        pub fn init(q: *Self, alloc: Allocator, workers: u32) !void {
            assert(workers > 0);
            q.* = .{
                .closed = .init(false),
                .cond = .init,
                .outstanding = .init(0),
                .queued = .init(0),
                .queues = undefined,
                .wait_mutex = .init,
            };

            q.queues = try alloc.alloc(Queue, workers);
            for (q.queues) |*local| local.* = .{};
        }

        pub fn deinit(q: *Self, alloc: Allocator) void {
            alloc.free(q.queues);
        }

        pub fn push(q: *Self, io: Io, worker_id: u32, job: *T) !void {
            const local = &q.queues[q.localIndex(worker_id)];

            var queued_before: usize = 0;

            {
                try local.mutex.lock(io);
                defer local.mutex.unlock(io);

                local.queue.push(job);

                _ = local.approx_len.fetchAdd(1, .release);
                _ = q.outstanding.fetchAdd(1, .release);

                queued_before = q.queued.fetchAdd(1, .release);
            }

            if (queued_before < q.queues.len) try q.wakeOne(io);
        }

        pub fn pop(q: *Self, io: Io, worker_id: u32) !*T {
            const home = q.localIndex(worker_id);
            while (true) {
                if (q.popFrom(io, home)) |job| return job;
                if (q.steal(io, home)) |job| return job;
                if (q.closed.load(.acquire)) return error.Closed;

                try q.wait_mutex.lock(io);
                defer q.wait_mutex.unlock(io);

                while (q.queued.load(.acquire) == 0 and !q.closed.load(.acquire)) {
                    try q.cond.wait(io, &q.wait_mutex);
                }
            }
        }

        pub fn taskDone(q: *Self, io: Io) bool {
            if (q.outstanding.fetchSub(1, .acq_rel) == 1) {
                q.closed.store(true, .release);
                q.wakeAll(io) catch {};
                return true;
            }
            return false;
        }

        pub fn wakeAll(q: *Self, io: Io) !void {
            try q.wait_mutex.lock(io);
            defer q.wait_mutex.unlock(io);
            q.cond.broadcast(io);
        }

        fn wakeOne(q: *Self, io: Io) !void {
            try q.wait_mutex.lock(io);
            defer q.wait_mutex.unlock(io);
            q.cond.signal(io);
        }

        fn localIndex(q: *Self, worker_id: u32) usize {
            return @as(usize, @intCast(worker_id)) % q.queues.len;
        }

        fn popFrom(q: *Self, io: Io, index: usize) ?*T {
            const local = &q.queues[index];
            if (local.approx_len.load(.acquire) == 0) return null;

            local.mutex.lock(io) catch return null;
            defer local.mutex.unlock(io);

            const job = local.queue.pop() orelse return null;
            _ = local.approx_len.fetchSub(1, .release);
            _ = q.queued.fetchSub(1, .acq_rel);
            return job;
        }

        fn steal(q: *Self, io: Io, home: usize) ?*T {
            var offset: usize = 1;
            while (offset < q.queues.len) : (offset += 1) {
                const index = (home + offset) % q.queues.len;
                if (q.queues[index].approx_len.load(.acquire) == 0) continue;
                if (q.popFrom(io, index)) |job| return job;
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
