const std = @import("std");
const atomic = std.atomic;
const Io = std.Io;
const Allocator = std.mem.Allocator;
const testing = std.testing;

const constants = @import("constants.zig");
const MAX_CONTEXT_SIZE = constants.MAX_CONTEXT_SIZE;
const datastruct = @import("datastruct.zig");
const SinglyLinkedList = datastruct.SinglyLinkedList;
const global = @import("global.zig");

const state = &global.state;
const Scheduler = @This();

queued: atomic.Value(u64),
workers: atomic.Value(?*Worker),
mutex: Io.Mutex,
cond: Io.Condition,
closed: atomic.Value(bool),
group: Io.Group,
io: Io,
queue: Queue,

pub fn init(self: *Scheduler, io: Io) !void {
    self.* = .{
        .queued = .init(0),
        .queue = .{},
        .workers = .init(null),
        .closed = .init(false),
        .mutex = .init,
        .group = .init,
        .cond = .init,
        .io = io,
    };

    for (0..state.cpu_count) |_| {
        try self.group.concurrent(io, Worker.run, .{self});
    }
}

pub fn push(self: *Scheduler, task: *Task) void {
    self.queue.push(task, self.io);
    const queued = self.queued.fetchAdd(1, .release);
    if (queued < state.cpu_count) self.cond.signal(self.io);
}

fn register(self: *Scheduler, worker: *Worker) void {
    var head = self.workers.load(.monotonic);
    while (true) {
        worker.next = head;
        head = self.workers.cmpxchgWeak(
            head,
            worker,
            .release,
            .monotonic,
        ) orelse break;
    }
}

pub fn deinit(self: *Scheduler) void {
    self.closed.store(true, .release);
    self.group.cancel(self.io);
}

const Worker = struct {
    queue: Queue,
    next: ?*Worker,
    target: ?*Worker,

    threadlocal var local: ?*Worker = null;

    pub fn run(scheduler: *Scheduler) Io.Cancelable!void {
        var self: Worker = .{
            .queue = .{},
            .next = null,
            .target = null,
        };

        local = &self;

        scheduler.register(&self);

        while (true) {
            const task = try self.pop(scheduler);
            _ = scheduler.queued.fetchSub(1, .acq_rel);
            task.callback(task);
        }
    }

    pub fn pop(self: *Worker, scheduler: *Scheduler) !*Task {
        while (true) {
            if (self.queue.pop(scheduler.io)) |task| return task;
            if (scheduler.queue.pop(scheduler.io)) |task| return task;

            for (0..state.cpu_count) |_| {
                const target = self.target orelse scheduler.workers.load(.acquire) orelse unreachable;
                self.target = target.next;

                if (target == self) continue;

                if (target.queue.pop(scheduler.io)) |task| return task;
            }

            try scheduler.mutex.lock(scheduler.io);
            defer scheduler.mutex.unlock(scheduler.io);

            while (scheduler.queued.load(.acquire) == 0 and !scheduler.closed.load(.acquire)) {
                try scheduler.cond.wait(scheduler.io, &scheduler.mutex);
            }
        }
    }
};

const Queue = struct {
    mutex: Io.Mutex = .init,
    tasks: SinglyLinkedList(Task) = .{},

    pub fn pop(self: *@This(), io: Io) ?*Task {
        self.mutex.lock(io) catch return null;
        defer self.mutex.unlock(io);

        return self.tasks.pop();
    }

    pub fn push(self: *@This(), task: *Task, io: Io) void {
        self.mutex.lock(io) catch return;
        defer self.mutex.unlock(io);

        return self.tasks.append(task);
    }
};

const Task = struct {
    callback: *const fn (*Task) void,

    next: ?*Task = null,
};

test "Scheduler" {
    const io = testing.io;

    var scheduler: Scheduler = undefined;
    try scheduler.init(io);
    defer scheduler.deinit();

    const TestTask = struct {
        const Self = @This();

        count: u64,
        task: Task,

        pub fn callback(task: *Task) void {
            const self: *Self = @fieldParentPtr("task", task);
            self.count += 1;
        }
    };

    var test_task = TestTask{
        .count = 0,
        .task = .{ .callback = TestTask.callback },
    };

    scheduler.push(&test_task.task);

    try io.sleep(.fromNanoseconds(50), .real);

    try testing.expectEqual(1, test_task.count);
}
