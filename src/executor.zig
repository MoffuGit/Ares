const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const atomic = std.atomic;
const builtin = std.builtin;
const posix = std.posix;
const system = posix.system;
const debug = std.debug;
const assert = debug.assert;

const App = @import("app.zig");
const chunks_pool = @import("chunk_pool.zig");
const ChunkAllocator = chunks_pool.ChunkAllocator;
const constants = @import("constants.zig");
const MAX_SIZE = constants.MAX_SIZE;
const datastruct = @import("datastruct.zig");
const MultiMpsc = datastruct.MultiMpsc;
const Loop = @import("loop.zig");
const Completion = Loop.Completion;
const Tasks = @import("tasks.zig");
const Task = Tasks.Task;
const TaskId = Tasks.TaskId;
const ent = @import("entity.zig");
const EntityStore = ent.EntityStore;
const AnyEntity = ent.AnyEntity;
const typeId = @import("typeId.zig");
const TypeInfo = typeId.TypeInfo;
const slotmap = datastruct.slotmap;
pub const ExecutorId = slotmap.Key;

const Queues = union(enum) {
    cancelations: Tasks.Cancelation,
    completions: Completion,
    timers: Completion,
    submissions: Completion,
};

pub const Executors = struct {
    mutex: Io.Mutex,
    entities: EntityStore,
    io: Io,
    tasks: Tasks,
    loop: Loop,
    future: Io.Future(void),
    stop: atomic.Value(bool) = .init(false),
    stopped: atomic.Value(bool) = .init(false),
    queues: MultiMpsc(Queues),
    chunks: Allocator,

    pub fn init(self: *@This(), arena: Allocator, chunks: Allocator, io: Io) !void {
        self.* = .{
            .mutex = .init,
            .entities = undefined,
            .queues = undefined,
            .loop = undefined,
            .tasks = undefined,
            .io = io,
            .future = undefined,
            .chunks = chunks,
        };

        try self.entities.init(arena, 100);
        try self.tasks.init(arena, self.chunks, io);
        try self.loop.init(io);
        errdefer self.loop.deinit();

        self.future = try io.concurrent(Executors.run, .{self});
        self.queues.init();
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
            self.destroy_dropped_entities();
            self.io.sleep(.fromNanoseconds(100), .real) catch {};
        }

        self.destroy_dropped_entities();
        self.flush();
        self.loop.run(.no_wait) catch {};
        self.loop.run(.until_done) catch {};
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
        while (self.queues.pop(.completions)) |completion| {
            self.loop.complete(completion);
        }
        while (self.queues.pop(.timers)) |completion| {
            self.loop.submit_timer(completion);
        }
        while (self.queues.pop(.submissions)) |completion| {
            self.loop.submit(completion);
        }
    }

    pub fn @"defer"(
        self: *@This(),
        function: anytype,
        context: anytype,
    ) !Cancelation {
        const task = self.tasks.create();

        task.@"defer"(function, context);
        self.queues.push(.completions, &task.completion);

        return .{ .executor = self, .id = task.id };
    }

    pub fn await(
        self: *@This(),
        function: anytype,
        context: anytype,
    ) !struct { Cancelation, Tasks.Waker } {
        const task = self.tasks.create();
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
        const task = self.tasks.create();

        task.timer(function, context, ms);
        self.queues.push(.timers, &task.completion);

        return .{ .executor = self, .id = task.id };
    }

    pub const Cancelation = struct {
        id: TaskId,
        executor: *Executors,

        pub fn cancel(self: *const Cancelation) void {
            if (self.executor.tasks.cancelation(self.id)) |can| {
                self.executor.queues.push(.cancelations, can);
            }
        }
    };

    pub fn new(self: *Executors, comptime T: type, function: anytype, args: anytype) !Executor(T) {
        const ptr = try self.chunks.create(T);
        errdefer self.chunks.destroy(ptr);

        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);

        const id = self.entities.insert(ptr);
        errdefer self.entities.recycle(id);

        const executor: Executor(T) = .init(self, &self.entities, id, ptr);
        const ctx: Context(T) = .new(self, executor);

        try @call(.always_inline, function, .{ ptr, ctx } ++ args);

        return executor;
    }

    pub fn get(self: *Executors, comptime T: type, executor: Executor(T)) !*T {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);

        return self.entities.get(T, executor.id());
    }

    fn destroy_dropped_entities(self: *Executors) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        while (self.entities.popDrop()) |drop| {
            const ptr, const key, const type_info = drop;
            type_info.deinit(ptr);
            type_info.destroy(ptr, self.chunks);
            self.entities.recycle(key);
        }
    }
};

pub fn Executor(comptime T: type) type {
    return struct {
        pub const EntityType = T;

        any: AnyEntity,
        mutex: *Io.Mutex,
        ptr: *T,

        pub fn new(executors: *Executors, args: anytype) !@This() {
            return try executors.new(T, T.init, args);
        }

        pub fn from(any: AnyEntity, executors: *Executors) ?@This() {
            assert(any.type_id == TypeInfo.init(T));
            if (!any.store.entities.contains(any.id)) return null;

            const ptr = any.store.get(T, any.id);
            return .{
                .any = any,
                .mutex = &executors.mutex,
                .ptr = ptr,
            };
        }

        pub fn get(self: @This(), executors: *Executors) !*T {
            return try executors.get(T, self);
        }

        pub fn init(executors: *Executors, store: *EntityStore, new_id: ExecutorId, ptr: *T) @This() {
            return .{
                .any = .init(store, new_id, TypeInfo.init(T)),
                .mutex = &executors.mutex,
                .ptr = ptr,
            };
        }

        pub fn id(self: *const @This()) ExecutorId {
            return self.any.id;
        }

        pub fn drop(self: @This(), io: Io) !void {
            try self.mutex.lock(io);
            defer self.mutex.unlock(io);

            self.any.drop();
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

        pub fn drop(self: *const @This()) !void {
            try self.executor.drop(self.executors.io);
        }

        pub fn get(self: *const @This()) !*T {
            return try self.executor.get(self.executors);
        }

        pub fn @"defer"(self: *const @This(), function: anytype, args: anytype) !Executors.Cancelation {
            const Args = @TypeOf(args);
            const TypeErased = struct {
                pub fn @"defer"(any: AnyEntity, executors: *Executors, _args: Args, res: anyerror!void) bool {
                    res catch return false;
                    const _executor = _Executor.from(any, executors) orelse return false;

                    const ctx: Context(T) = .new(executors, _executor);

                    return @call(.always_inline, function, .{ctx} ++ _args);
                }
            };
            return self.executors.@"defer"(TypeErased.@"defer", .{ self.executor.any, self.executors, args });
        }

        pub fn await(self: *const @This(), function: anytype, args: anytype) !struct { Executors.Cancelation, Tasks.Waker } {
            const Args = @TypeOf(args);
            const TypeErased = struct {
                pub fn async(any: AnyEntity, executors: *Executors, _args: Args, res: anyerror!void) bool {
                    res catch return false;
                    const _executor = _Executor.from(any, executors) orelse return false;

                    const ctx: Context(T) = .new(executors, _executor);

                    return @call(.always_inline, function, .{ctx} ++ _args);
                }
            };

            return self.executors.await(TypeErased.async, .{ self.executor.any, self.executors, args });
        }

        pub fn timer(self: *const @This(), function: anytype, args: anytype, ms: u64) !Executors.Cancelation {
            const Args = @TypeOf(args);
            const TypeErased = struct {
                pub fn timer(any: AnyEntity, executors: *Executors, _args: Args, res: anyerror!void) bool {
                    res catch return false;
                    const _executor = _Executor.from(any, executors) orelse return false;

                    const ctx: Context(T) = .new(executors, _executor);

                    return @call(.always_inline, function, .{ctx} ++ _args);
                }
            };
            return self.executors.timer(TypeErased.timer, .{ self.executor.any, self.executors, args }, ms);
        }
    };
}
