//SOURCE: https://github.com/dmtrKovalenko/zlob
//LICENSE: [ZLOB]

const std = @import("std");
const Io = std.Io;
const atomic = std.atomic;
const Allocator = std.mem.Allocator;

const queue = @import("queue.zig");

pub fn StealingQueue(T: type) type {
    return struct {
        const Self = @This();

        const Queue = struct {
            mutex: Io.Mutex = .init,
            queue: queue.Intrusive(T) = .{},
            approx_len: atomic.Value(usize) = .init(0),
        };

        queues: []Queue = &.{},
        wait_mutex: Io.Mutex = .init,
        cond: Io.Condition = .init,
        queued: atomic.Value(usize) = .init(0),
        outstanding: atomic.Value(usize) = .init(0),
        closed: atomic.Value(bool) = .init(false),

        pub fn init(q: *Self, arena: Allocator, workers: u32) !void {
            const n: usize = @max(1, @as(usize, @intCast(workers)));
            q.queues = try arena.alloc(Queue, n);
            for (q.queues) |*local| local.* = .{};
        }

        pub fn push(q: *Self, io: Io, worker_id: u32, job: *T) void {
            const local = &q.queues[q.localIndex(worker_id)];
            local.mutex.lockUncancelable(io);
            local.queue.push(job);
            _ = local.approx_len.fetchAdd(1, .release);
            _ = q.outstanding.fetchAdd(1, .release);
            const queued_before = q.queued.fetchAdd(1, .release);
            local.mutex.unlock(io);
            if (queued_before < q.queues.len) q.wakeOne(io);
        }

        pub fn pop(q: *Self, io: Io, worker_id: u32) ?*T {
            const home = q.localIndex(worker_id);
            while (true) {
                if (q.popFrom(io, home)) |job| return job;
                if (q.steal(io, home)) |job| return job;
                if (q.closed.load(.acquire)) return null;

                q.wait_mutex.lockUncancelable(io);
                while (q.queued.load(.acquire) == 0 and !q.closed.load(.acquire)) {
                    q.cond.waitUncancelable(io, &q.wait_mutex);
                }
                q.wait_mutex.unlock(io);
            }
        }

        pub fn taskDone(q: *Self, io: Io) bool {
            if (q.outstanding.fetchSub(1, .acq_rel) == 1) {
                q.closed.store(true, .release);
                q.wakeAll(io);
                return true;
            }
            return false;
        }

        pub fn wakeAll(q: *Self, io: Io) void {
            q.wait_mutex.lockUncancelable(io);
            defer q.wait_mutex.unlock(io);
            q.cond.broadcast(io);
        }

        fn wakeOne(q: *Self, io: Io) void {
            q.wait_mutex.lockUncancelable(io);
            defer q.wait_mutex.unlock(io);
            q.cond.signal(io);
        }

        fn localIndex(q: *Self, worker_id: u32) usize {
            return @as(usize, @intCast(worker_id)) % q.queues.len;
        }

        fn popFrom(q: *Self, io: Io, index: usize) ?*T {
            const local = &q.queues[index];
            if (local.approx_len.load(.acquire) == 0) return null;
            local.mutex.lockUncancelable(io);
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
    };
}
