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

pub const Scheduler = struct {
    tasks: Tasks,
    loop: Loop,
    options: App.Options,

    pub fn init(self: *Scheduler, options: App.Options, arena: Allocator, chunks: Allocator, gpa: Allocator, io: Io) !void {
        self.options = options;
        try self.tasks.init(arena, chunks, gpa, io);
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

        task.complete(&self.loop);

        return .{ .id = task.id, .scheduler = self };
    }

    pub fn await(
        self: *Scheduler,
        function: anytype,
        context: anytype,
    ) !Waker {
        const task = self.tasks.create();
        const port = try task.await(function, context);

        task.submit(&self.loop);

        return .{ .port = port, .cancelation = .{ .id = task.id, .scheduler = self } };
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

    pub const Waker = struct {
        port: system.mach_port_name_t,
        cancelation: Cancelation,

        pub fn wake(self: *const Waker) !void {
            var msg: posix.system.mach_msg_header_t = .{
                .msgh_bits = @intFromEnum(system.MACH.MSG.TYPE.COPY_SEND),
                .msgh_size = @sizeOf(posix.system.mach_msg_header_t),
                .msgh_remote_port = self.port,
                .msgh_local_port = system.MACH.PORT.NULL,
                .msgh_voucher_port = undefined,
                .msgh_id = undefined,
            };

            switch (system.mach_msg(
                &msg,
                .{ .SEND = .{ .TIMEOUT = true, .MSG = true } },
                msg.msgh_size,
                0,
                system.MACH.PORT.NULL,
                @enumFromInt(0),
                system.MACH.PORT.NULL,
            )) {
                .SUCCESS => {},
                .SEND_NO_BUFFER => {},
                .SEND_TIMED_OUT => {},
                else => |e| {
                    std.log.warn("mach msg err={}", .{e});
                    return error.MachMsgFailed;
                },
            }

            self.cancelation.scheduler.wakeup();
        }

        pub fn close(self: *const Waker) void {
            self.cancelation.cancel();
            _ = system.mach_port_deallocate(
                posix.system.mach_task_self(),
                self.port,
            );
        }
    };

    fn wakeup(self: *@This()) void {
        self.options.wakeup_cb(self.options.userdata);
    }
};

const Queues = union(enum) {
    cancelations: Tasks.Cancelation,
    completions: Task,
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
    gpa: Allocator,
    queues: multi_mpsc.MultiIntrusive(Queues),
    chunks: ChunkAllocator,
    options: App.Options,

    pub fn init(self: *@This(), options: App.Options, arena: Allocator, gpa: Allocator, io: Io) !void {
        self.* = .{
            .options = options,
            .queues = undefined,
            .loop = undefined,
            .tasks = undefined,
            .io = io,
            .future = undefined,
            .arena = arena,
            .gpa = gpa,
            .chunks = undefined,
        };

        self.queues.init();
        try self.chunks.init(self.arena, 100, .{MAX_SIZE});
        try self.tasks.init(arena, self.chunks.allocator(), gpa, io);
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
            task.complete(&self.loop);
        }
        while (self.queues.pop(.submissions)) |task| {
            task.submit(&self.loop);
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
    ) !Waker {
        const task = self.tasks.create();
        const port = try task.await(function, context);

        self.queues.push(.submissions, task);

        return .{ .port = port, .cancelation = .{ .id = task.id, .scheduler = self } };
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

    pub const Waker = struct {
        port: system.mach_port_name_t,
        cancelation: Cancelation,

        pub fn wake(self: *const Waker) !void {
            var msg: posix.system.mach_msg_header_t = .{
                .msgh_bits = @intFromEnum(system.MACH.MSG.TYPE.COPY_SEND),
                .msgh_size = @sizeOf(posix.system.mach_msg_header_t),
                .msgh_remote_port = self.port,
                .msgh_local_port = system.MACH.PORT.NULL,
                .msgh_voucher_port = undefined,
                .msgh_id = undefined,
            };

            switch (system.mach_msg(
                &msg,
                .{ .SEND = .{ .TIMEOUT = true, .MSG = true } },
                msg.msgh_size,
                0,
                system.MACH.PORT.NULL,
                @enumFromInt(0),
                system.MACH.PORT.NULL,
            )) {
                .SUCCESS => {},
                .SEND_NO_BUFFER => {},
                .SEND_TIMED_OUT => {},
                else => |e| {
                    std.log.warn("mach msg err={}", .{e});
                    return error.MachMsgFailed;
                },
            }
        }

        pub fn close(self: *const Waker) void {
            self.cancelation.cancel();
            _ = system.mach_port_deallocate(
                posix.system.mach_task_self(),
                self.port,
            );
        }
    };

    pub fn Executor(T: type) type {
        return struct {
            ptr: *T,
            waker: Waker,
            arena: Allocator,

            pub fn init(self: *@This(), args: anytype) !void {
                try @call(.always_inline, T.init, .{ self.ptr, self.arena, self.waker } ++ args);
            }

            pub fn stop(self: *@This()) void {
                self.waker.close();
            }
        };
    }

    pub fn executor(self: *@This(), T: type, function: anytype, args: anytype) !Executor(T) {
        const task = self.tasks.create();
        const arena = task.arena.allocator();
        const ptr = try arena.create(T);
        const port = try task.await(function, .{ptr} ++ args);
        self.queues.push(.submissions, task);

        return .{
            .ptr = ptr,
            .waker = .{
                .cancelation = .{
                    .id = task.id,
                    .scheduler = self,
                },
                .port = port,
            },
            .arena = arena,
        };
    }
};

test "Background Scheduler runs deferred tasks and frees memory on stop" {
    const testing = std.testing;
    const heap = std.heap;

    var arena: heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    var scheduler: BackgroundScheduler = undefined;
    try scheduler.init(.{}, arena.allocator(), testing.allocator, testing.io);
    defer scheduler.deinit();

    var called = false;
    _ = try scheduler.@"defer"(struct {
        fn callback(_called: *bool, _arena: Allocator, res: anyerror!void) bool {
            res catch return false;
            _ = _arena.alloc(u8, 16) catch return false;
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
    try scheduler.init(.{}, arena.allocator(), testing.allocator, testing.io);
    defer scheduler.deinit();

    var called = false;
    const waker = try scheduler.await(struct {
        fn callback(_called: *bool, _arena: Allocator, res: anyerror!void) bool {
            res catch return false;
            _ = _arena.alloc(u8, 16) catch return false;
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

test "Executor cancels await tasks and frees memory on stop" {
    const testing = std.testing;
    const heap = std.heap;

    var arena: heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    var executor: BackgroundScheduler = undefined;
    try executor.init(.{}, arena.allocator(), testing.allocator, testing.io);
    defer executor.deinit();

    var canceled = false;
    const waker = try executor.await(struct {
        fn callback(_canceled: *bool, allocator: Allocator, res: anyerror!void) bool {
            if (res == error.Canceled) {
                _ = allocator.alloc(u8, 16) catch return false;
                _canceled.* = true;
            }
            return false;
        }
    }.callback, .{&canceled});

    waker.close();
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
    try scheduler.init(.{}, arena.allocator(), testing.allocator, testing.io);
    defer scheduler.deinit();

    const State = struct {
        value: u32,

        fn init(self: *@This(), _: Allocator, _: BackgroundScheduler.Waker, value: u32) !void {
            self.value = value;
        }
    };

    var called = false;
    var value: u32 = 0;
    var executor = try scheduler.executor(State, struct {
        fn callback(state: *State, _called: *bool, _value: *u32, alloc: Allocator, res: anyerror!void) bool {
            res catch return false;
            _ = alloc.alloc(u8, 16) catch return false;
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
    try chunks.init(arena.allocator(), 100, .{MAX_SIZE});

    var scheduler: Scheduler = undefined;
    try scheduler.init(.{
        .userdata = &wakeups,
        .wakeup_cb = struct {
            fn callback(userdata: *anyopaque) callconv(.c) void {
                const count: *usize = @ptrCast(@alignCast(userdata));
                count.* += 1;
            }
        }.callback,
    }, arena.allocator(), chunks.allocator(), testing.allocator, testing.io);
    defer scheduler.deinit();

    const waker = try scheduler.await(struct {
        fn callback(_: Allocator, res: anyerror!void) bool {
            res catch return false;
            return false;
        }
    }.callback, .{});
    defer waker.close();

    try waker.wake();

    try testing.expectEqual(@as(usize, 1), wakeups);
}
