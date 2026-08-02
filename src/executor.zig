const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const atomic = std.atomic;

const App = @import("app.zig");
const Receivers = App.Receivers;
const datastruct = @import("datastruct.zig");
const MultiMpsc = datastruct.MultiMpsc;
const Queue = datastruct.Queue;
const Loop = @import("loop.zig");
const Completion = Loop.Completion;
const Runner = @import("runner.zig");
const Task = Runner.Task;
const TaskId = Runner.TaskId;
const typeId = @import("typeId.zig");
const TypeInfo = typeId.TypeInfo;
const TypeId = typeId.TypeId;

const Dropped = struct { ptr: *anyopaque, type_id: TypeId, next: ?*Dropped = null };

const Queues = union(enum) {
    cancelations: Completion,
    completions: Completion,
    dropped: Dropped,
    timers: Completion,
    submissions: Completion,
};

pub const Batched = struct {
    subscription: Receivers.Subscription,
    type: TypeId,
    ptr: *anyopaque,

    next: ?*Batched = null,

    pub fn destroy(self: *const Batched, chunk: Allocator) void {
        self.type.deinit(self.ptr);
        self.type.destroy(self.ptr, chunk);
    }
};
pub const Batch = Queue(Batched);

pub const Batcher = struct {
    mutex: Io.Mutex,
    batches: std.Deque(Batch),

    pub fn init(self: *Batcher, arena: Allocator) !void {
        self.* = .{ .mutex = .init, .batches = try .initCapacity(arena, 100) };
    }

    pub fn lock(self: *Batcher, io: Io) !void {
        try self.mutex.lock(io);
    }

    pub fn unlock(self: *Batcher, io: Io) void {
        self.mutex.unlock(io);
    }
};

pub const Executors = struct {
    io: Io,
    runner: Runner,
    future: Io.Future(void),
    stop: atomic.Value(bool) = .init(false),
    queues: MultiMpsc(Queues),
    chunks: Allocator,
    batcher: Batcher,
    batch: Batch = .{},

    pub fn init(
        self: *@This(),
        arena: Allocator,
        chunks: Allocator,
        io: Io,
    ) !void {
        self.* = .{
            .queues = undefined,
            .runner = undefined,
            .io = io,
            .future = undefined,
            .chunks = chunks,
            .batcher = undefined,
        };

        try self.batcher.init(arena);

        try self.runner.init(arena, self.chunks, io);
        errdefer self.runner.deinit();

        self.future = try io.concurrent(Executors.run, .{self});
        self.queues.init();
    }

    pub fn deinit(self: *@This()) void {
        self.stop.store(true, .release);
        _ = self.future.await(self.io);
        self.runner.deinit();
    }

    fn run(self: *@This()) void {
        while (!self.stop.load(.acquire)) {
            self.publishBatch() catch return;
            self.flush();
            self.runner.run(.no_wait) catch return;
            self.destroyDroppedExecutors() catch return;
            self.io.sleep(.fromNanoseconds(100), .real) catch {};
        }

        self.flush();
        self.runner.run(.no_wait) catch return;
        self.destroyDroppedExecutors() catch return;
    }

    fn publishBatch(self: *@This()) !void {
        if (self.batch.empty()) return;

        {
            try self.batcher.lock(self.io);
            defer self.batcher.unlock(self.io);

            try self.batcher.batches.pushBackBounded(self.batch);
        }

        self.batch = .{};
    }

    fn addQueuedTasks(self: *@This()) void {
        while (self.queues.pop(.completions)) |completion| {
            const task: *Task = @fieldParentPtr("completion", completion);
            self.runner.complete(task);
        }
        while (self.queues.pop(.timers)) |completion| {
            const task: *Task = @fieldParentPtr("completion", completion);
            self.runner.submitTimer(task);
        }
        while (self.queues.pop(.submissions)) |completion| {
            const task: *Task = @fieldParentPtr("completion", completion);
            self.runner.submit(task);
        }
    }

    fn flush(self: *@This()) void {
        self.addQueuedTasks();

        while (self.queues.pop(.cancelations)) |completion| {
            const cancelation: *Runner.Cancelation = @fieldParentPtr("completion", completion);
            self.runner.cancel(cancelation);
        }
    }

    pub fn @"defer"(
        self: *@This(),
        function: anytype,
        context: anytype,
    ) !Cancelation {
        const task = self.runner.create();

        task.@"defer"(function, context);
        self.queues.push(.completions, &task.completion);

        return .{ .executor = self, .id = task.id };
    }

    pub fn await(
        self: *@This(),
        function: anytype,
        context: anytype,
    ) !struct { Cancelation, Runner.Waker } {
        const task = self.runner.create();
        errdefer self.runner.destroyUnregistered(task);
        const waker = try task.await(function, context);

        self.queues.push(.submissions, &task.completion);

        return .{
            Cancelation{ .id = task.id, .executor = self },
            waker,
        };
    }

    pub fn timer(
        self: *@This(),
        function: anytype,
        context: anytype,
        ms: u64,
    ) !Cancelation {
        const task = self.runner.create();

        task.timer(function, context, ms);
        self.queues.push(.timers, &task.completion);

        return .{ .executor = self, .id = task.id };
    }

    pub const Cancelation = struct {
        id: TaskId,
        executor: *Executors,

        pub fn cancel(self: *const Cancelation) void {
            const cancelation = self.executor.runner.createCancelation(self.id);
            self.executor.queues.push(.cancelations, &cancelation.completion);
        }
    };

    pub fn new(self: *Executors, comptime T: type, function: anytype, args: anytype) !Executor(T) {
        const ptr = try self.chunks.create(T);
        const executor: Executor(T) = .init(self, ptr);
        const ctx: Context(T) = .new(self, executor);

        try @call(.always_inline, function, .{ ptr, ctx } ++ args);

        return executor;
    }

    fn queueDrop(self: *Executors, ptr: *anyopaque, type_id: TypeId) void {
        const dropped = self.chunks.create(Dropped) catch @panic("Dropped Executor Overflow");
        dropped.* = .{ .ptr = ptr, .type_id = type_id };
        self.queues.push(.dropped, dropped);
    }

    fn destroyDroppedExecutors(self: *Executors) !void {
        while (self.queues.pop(.dropped)) |dropped| {
            dropped.type_id.deinit(dropped.ptr);
            dropped.type_id.destroy(dropped.ptr, self.chunks);
            self.chunks.destroy(dropped);
        }
    }
};

pub fn Executor(comptime T: type) type {
    return struct {
        ptr: *T,
        executors: *Executors,

        pub fn new(executors: *Executors, args: anytype) !@This() {
            return try executors.new(T, T.init, args);
        }

        fn init(executors: *Executors, ptr: *T) @This() {
            return .{
                .ptr = ptr,
                .executors = executors,
            };
        }

        pub fn drop(self: @This()) void {
            const type_id = TypeInfo.init(T);
            type_id.drop(self.ptr);
            self.executors.queueDrop(self.ptr, type_id);
        }
    };
}

pub fn Context(comptime T: type) type {
    return struct {
        const _Executor = Executor(T);

        executors: *Executors,
        executor: _Executor,

        pub fn new(executors: *Executors, executor: _Executor) @This() {
            return .{ .executors = executors, .executor = executor };
        }

        pub fn drop(self: *const @This()) void {
            self.executor.drop();
        }

        pub fn get(self: *const @This()) *T {
            return self.executor.ptr;
        }

        pub fn @"defer"(self: *const @This(), function: anytype, args: anytype) !Executors.Cancelation {
            const Args = @TypeOf(args);
            const TypeErased = struct {
                pub fn @"defer"(_executor: _Executor, executors: *Executors, _args: Args, res: anyerror!void) bool {
                    res catch return false;
                    const ctx: Context(T) = .new(executors, _executor);

                    return @call(.always_inline, function, .{ctx} ++ _args);
                }
            };
            return self.executors.@"defer"(TypeErased.@"defer", .{ self.executor, self.executors, args });
        }

        pub fn await(self: *const @This(), function: anytype, args: anytype) !struct { Executors.Cancelation, Runner.Waker } {
            const Args = @TypeOf(args);
            const TypeErased = struct {
                pub fn async(_executor: _Executor, executors: *Executors, _args: Args, res: anyerror!void) bool {
                    res catch return false;
                    const ctx: Context(T) = .new(executors, _executor);

                    return @call(.always_inline, function, .{ctx} ++ _args);
                }
            };

            return self.executors.await(TypeErased.async, .{ self.executor, self.executors, args });
        }

        pub fn timer(self: *const @This(), function: anytype, args: anytype, ms: u64) !Executors.Cancelation {
            const Args = @TypeOf(args);
            const TypeErased = struct {
                pub fn timer(_executor: _Executor, executors: *Executors, _args: Args, res: anyerror!void) bool {
                    res catch return false;
                    const ctx: Context(T) = .new(executors, _executor);

                    return @call(.always_inline, function, .{ctx} ++ _args);
                }
            };
            return self.executors.timer(TypeErased.timer, .{ self.executor, self.executors, args }, ms);
        }

        pub fn dispatch(self: *const @This(), subscription: Receivers.Subscription, comptime E: type) !*E {
            const chunks = self.executors.chunks;
            const ptr = try chunks.create(E);
            errdefer chunks.destroy(ptr);

            const batched = try chunks.create(Batched);
            batched.* = .{
                .subscription = subscription,
                .type = TypeInfo.init(E),
                .ptr = ptr,
            };

            self.executors.batch.push(batched);

            return ptr;
        }
    };
}
