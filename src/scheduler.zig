const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const atomic = std.atomic;
const builtin = std.builtin;
const posix = std.posix;
const system = posix.system;
const constants = @import("contants.zig");
const MAX_SIZE = constants.MAX_SIZE;

const chunks_pool = @import("chunk_pool.zig");
const ChunkAllocator = chunks_pool.ChunkAllocator;
const datastruct = @import("datastruct.zig");
const multi_mpsc = datastruct.multi_mpsc;
const Loop = @import("loop.zig");
const Tasks = @import("tasks.zig");
const Task = Tasks.Task;
const TaskId = Tasks.TaskId;
const App = @import("app.zig");

pub const Waker = struct {
    waker: Tasks.Waker,
    options: App.Options,
    cancelation: Scheduler.Cancelation,

    pub fn wake(self: *const Waker) !void {
        try self.waker.wake();
        self.options.wakeup_cb(self.options.userdata);
    }

    pub fn close(self: *const Waker) void {
        self.waker.close();
        self.cancelation.cancel();
    }
};

pub const Scheduler = struct {
    tasks: Tasks,
    loop: Loop,
    options: App.Options,

    pub fn init(self: *Scheduler, options: App.Options, arena: Allocator, chunks: Allocator, io: Io) !void {
        self.options = options;
        try self.tasks.init(arena, chunks, io);
        try self.loop.init(io);
    }

    pub fn deinit(self: *Scheduler) void {
        self.loop.deinit();
    }

    pub fn run(self: *Scheduler) !void {
        try self.loop.run(.no_wait);
    }

    pub fn @"defer"(
        self: *Scheduler,
        function: anytype,
        context: anytype,
    ) Cancelation {
        const task = self.tasks.create();
        task.@"defer"(function, context);

        self.loop.complete(&task.completion);

        return .{ .id = task.id, .scheduler = self };
    }

    pub fn await(
        self: *Scheduler,
        function: anytype,
        context: anytype,
    ) !Waker {
        const task = self.tasks.create();
        const waker = try task.await(function, context);

        self.loop.submit(&task.completion);

        return .{
            .waker = waker,
            .options = self.options,
            .cancelation = .{
                .id = task.id,
                .scheduler = self,
            },
        };
    }

    pub const Cancelation = struct {
        id: TaskId,
        scheduler: *Scheduler,

        pub fn cancel(self: *const Cancelation) void {
            if (self.scheduler.tasks.cancelation(self.id)) |can| {
                self.scheduler.loop.cancel(&can.completion);
            }
        }
    };

    fn wakeup(self: *@This()) void {
        self.options.wakeup_cb(self.options.userdata);
    }
};

const Queues = union(enum) {
    cancelations: Tasks.Cancelation,
    completions: Task,
    timers: Task,
    submissions: Task,
};

pub const BackgroundScheduler = struct {
    tasks: Tasks,
    loop: Loop,

    io: Io,
    future: Io.Future(void),
    stop: atomic.Value(bool) = .init(false),
    stopped: atomic.Value(bool) = .init(false),
    arena: Allocator,
    queues: multi_mpsc.MultiIntrusive(Queues),
    chunks: ChunkAllocator,
    options: App.Options,

    pub fn init(self: *@This(), options: App.Options, arena: Allocator, io: Io) !void {
        self.* = .{
            .options = options,
            .queues = undefined,
            .loop = undefined,
            .tasks = undefined,
            .io = io,
            .future = undefined,
            .arena = arena,
            .chunks = undefined,
        };

        self.queues.init();
        try self.chunks.initThreadSafe(io, self.arena, &.{ .{ 10, MAX_SIZE }, .{ 10, 1280 } });
        try self.tasks.init(arena, self.chunks.threadSafeAllocator(), io);
        try self.loop.init(io);
        errdefer self.loop.deinit();

        self.future = try io.concurrent(BackgroundScheduler.run, .{self});
    }

    pub fn deinit(self: *@This()) void {
        self.stop.store(true, .release);

        while (!self.stopped.load(.acquire)) {
            self.io.sleep(.fromNanoseconds(100), .real) catch {};
        }

        _ = self.future.await(self.io);
        self.loop.deinit();
    }

    fn run(self: *@This()) void {
        while (!self.stop.load(.acquire)) {
            self.flush();
            self.loop.run(.no_wait) catch return;
            self.io.sleep(.fromNanoseconds(100), .real) catch {};
        }

        self.flush();
        self.loop.run(.until_done) catch return;
        self.stopped.store(true, .release);
    }

    fn flush(self: *@This()) void {
        while (self.queues.pop(.cancelations)) |cancelation| {
            if (self.tasks.contains(cancelation.id)) {
                cancelation.cancel(&self.loop);
            } else {
                self.tasks.destroy_cancelation(cancelation);
            }
        }
        while (self.queues.pop(.completions)) |task| {
            self.loop.complete(&task.completion);
        }
        while (self.queues.pop(.timers)) |task| {
            self.loop.submit_timer(&task.completion);
        }
        while (self.queues.pop(.submissions)) |task| {
            self.loop.submit(&task.completion);
        }
    }

    pub fn @"defer"(
        self: *@This(),
        function: anytype,
        context: anytype,
    ) !Cancelation {
        const task = self.tasks.create();

        task.@"defer"(function, context);
        self.queues.push(.completions, task);

        return .{ .scheduler = self, .id = task.id };
    }

    pub fn await(
        self: *@This(),
        function: anytype,
        context: anytype,
    ) !struct { Cancelation, Tasks.Waker } {
        const task = self.tasks.create();
        const waker = try task.await(function, context);

        self.queues.push(.submissions, task);

        return .{
            Cancelation{ .id = task.id, .scheduler = self },
            waker,
        };
    }

    pub fn timer(
        self: *@This(),
        function: anytype,
        context: anytype,
        ms: u64,
    ) !Cancelation {
        const task = self.tasks.create();

        task.timer(function, context, ms);
        self.queues.push(.timers, task);

        return .{ .scheduler = self, .id = task.id };
    }

    pub const Cancelation = struct {
        id: TaskId,
        scheduler: *BackgroundScheduler,

        pub fn cancel(self: *const Cancelation) void {
            if (self.scheduler.tasks.cancelation(self.id)) |can| {
                self.scheduler.queues.push(.cancelations, can);
            }
        }
    };

    pub fn Executor(T: type) type {
        return struct {
            ptr: *T,
            waker: Tasks.Waker,
            cancelation: Cancelation,

            pub fn init(self: *@This(), args: anytype) !void {
                try @call(.always_inline, T.init, .{ self.ptr, self.waker } ++ args);
            }

            pub fn stop(self: *@This()) void {
                self.waker.close();
                self.cancelation.cancel();
            }
        };
    }

    pub const Context = struct {
        waker: Tasks.Waker,
        scheduler: *BackgroundScheduler,
    };

    pub fn executor(self: *@This(), T: type, function: anytype, args: anytype) !Executor(T) {
        const Args = @TypeOf(args);

        const alloc = self.chunks.threadSafeAllocator();

        const ptr = try alloc.create(T);
        errdefer alloc.destroy(ptr);

        const task = self.tasks.create();

        const TypeErased = struct {
            fn callback(scheduler: *BackgroundScheduler, _ptr: *T, _task: *Task, _args: Args, res: anyerror!void) bool {
                const port = _task.completion.operation.machport.port;

                const rearm = @call(.always_inline, function, .{ _ptr, Context{ .scheduler = scheduler, .waker = .{ .port = port } } } ++ _args ++ .{res});
                if (!rearm) {
                    const _alloc = scheduler.chunks.threadSafeAllocator();
                    _alloc.destroy(_ptr);
                }

                return rearm;
            }
        };
        const waker = try task.await(TypeErased.callback, .{ self, ptr, task, args });
        self.queues.push(.submissions, task);

        return .{
            .ptr = ptr,
            .waker = waker,
            .cancelation = .{
                .scheduler = self,
                .id = task.id,
            },
        };
    }
};
//
test "Background Scheduler runs deferred tasks and frees memory on stop" {
    const testing = std.testing;
    const heap = std.heap;

    var arena: heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    var scheduler: BackgroundScheduler = undefined;
    try scheduler.init(.{}, arena.allocator(), testing.io);
    defer scheduler.deinit();

    var called = false;
    _ = try scheduler.@"defer"(struct {
        fn callback(_called: *bool, res: anyerror!void) bool {
            res catch return false;
            _called.* = true;
            return false;
        }
    }.callback, .{&called});

    while (!called) {
        testing.io.sleep(.fromNanoseconds(100), .real) catch {};
    }
}

test "Background Scheduler runs await tasks and frees memory on close" {
    const testing = std.testing;
    const heap = std.heap;

    var arena: heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    var scheduler: BackgroundScheduler = undefined;
    try scheduler.init(.{}, arena.allocator(), testing.io);
    defer scheduler.deinit();

    var called = false;
    _, const waker = try scheduler.await(struct {
        fn callback(_called: *bool, res: anyerror!void) bool {
            res catch return false;
            _called.* = true;
            return false;
        }
    }.callback, .{&called});

    try waker.wake();
    while (!called) {
        testing.io.sleep(.fromNanoseconds(100), .real) catch {};
    }
    waker.close();
}

test "Background Scheduler runs timer tasks" {
    const testing = std.testing;
    const heap = std.heap;

    var arena: heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    var scheduler: BackgroundScheduler = undefined;
    try scheduler.init(.{}, arena.allocator(), testing.io);
    defer scheduler.deinit();

    var called = false;
    _ = try scheduler.timer(struct {
        fn callback(_called: *bool, res: anyerror!void) bool {
            res catch return false;
            _called.* = true;
            return false;
        }
    }.callback, .{&called}, 0);

    while (!called) {
        testing.io.sleep(.fromNanoseconds(100), .real) catch {};
    }
}

test "Background Scheduler cancels timer tasks" {
    const testing = std.testing;
    const heap = std.heap;

    var arena: heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    var scheduler: BackgroundScheduler = undefined;
    try scheduler.init(.{}, arena.allocator(), testing.io);
    defer scheduler.deinit();

    var canceled = false;
    const cancelation = try scheduler.timer(struct {
        fn callback(_canceled: *bool, res: anyerror!void) bool {
            if (res == error.Canceled) {
                _canceled.* = true;
            }
            return false;
        }
    }.callback, .{&canceled}, std.time.ms_per_s);

    cancelation.cancel();

    while (!canceled) {
        testing.io.sleep(.fromNanoseconds(100), .real) catch {};
    }
}

test "Scheduler cancels await tasks and frees memory on stop" {
    const testing = std.testing;
    const heap = std.heap;

    var arena: heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    var scheduler: BackgroundScheduler = undefined;
    try scheduler.init(.{}, arena.allocator(), testing.io);
    defer scheduler.deinit();

    var canceled = false;
    const cancel, const waker = try scheduler.await(struct {
        fn callback(_canceled: *bool, res: anyerror!void) bool {
            if (res == error.Canceled) {
                _canceled.* = true;
            }
            return false;
        }
    }.callback, .{&canceled});

    waker.close();
    cancel.cancel();
    while (!canceled) {
        testing.io.sleep(.fromNanoseconds(100), .real) catch {};
    }
}

test "Background Scheduler comptime Executor initializes and wakes task" {
    const testing = std.testing;
    const heap = std.heap;

    var arena: heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    var scheduler: BackgroundScheduler = undefined;
    try scheduler.init(.{}, arena.allocator(), testing.io);
    defer scheduler.deinit();

    const State = struct {
        value: u32,

        fn init(self: *@This(), _: Tasks.Waker, value: u32) !void {
            self.value = value;
        }
    };

    var called = false;
    var value: u32 = 0;
    var executor = try scheduler.executor(State, struct {
        fn callback(state: *State, _: BackgroundScheduler.Context, _called: *bool, _value: *u32, res: anyerror!void) bool {
            res catch return false;
            _value.* = state.value;
            _called.* = true;
            return false;
        }
    }.callback, .{ &called, &value });

    try executor.init(.{42});
    try executor.waker.wake();
    while (!called) {
        testing.io.sleep(.fromNanoseconds(100), .real) catch {};
    }

    try testing.expectEqual(@as(u32, 42), value);
}

test "Scheduler waker calls wakeup callback" {
    const testing = std.testing;
    const heap = std.heap;

    var arena: heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    var wakeups: usize = 0;
    var chunks: ChunkAllocator = undefined;
    try chunks.init(arena.allocator(), &.{.{ 100, MAX_SIZE }});

    var scheduler: Scheduler = undefined;
    try scheduler.init(.{
        .userdata = &wakeups,
        .wakeup_cb = struct {
            fn callback(userdata: *anyopaque) callconv(.c) void {
                const count: *usize = @ptrCast(@alignCast(userdata));
                count.* += 1;
            }
        }.callback,
    }, arena.allocator(), chunks.allocator(), testing.io);
    defer scheduler.deinit();

    const waker = try scheduler.await(struct {
        fn callback(res: anyerror!void) bool {
            res catch return false;
            return false;
        }
    }.callback, .{});
    defer waker.close();

    try waker.wake();

    try testing.expectEqual(@as(usize, 1), wakeups);
}
