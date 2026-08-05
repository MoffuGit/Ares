const std = @import("std");
const Allocator = std.mem.Allocator;
const atomic = std.atomic;
const posix = std.posix;
const system = posix.system;
const testing = std.testing;
const heap = std.heap;
const debug = std.debug;
const panic = debug.panic;
const Io = std.Io;

const App = @import("app.zig");
const Receiver = App.Receiver;
const Batch = App.Batch;
const Batched = App.Batched;
const Producer = App.Producer;
const AppWaker = App.Waker;
const chunk_pool = @import("chunk_pool.zig");
const ChunkAllocator = chunk_pool.ChunkAllocator;
const constants = @import("constants.zig");
const MAX_SIZE = constants.MAX_SIZE;
const MAX_ALIGN = constants.MAX_ALIGN;
const datastruct = @import("datastruct.zig");
const MultiMpsc = datastruct.MultiMpsc;
const Queue = datastruct.Queue;
const SpscBounded = datastruct.SpscBounded;
const Loop = @import("loop.zig");
const Completion = Loop.Completion;
const RunMode = Loop.RunMode;
const typeId = @import("typeId.zig");
const TypeInfo = typeId.TypeInfo;
const TypeId = typeId.TypeId;

const log = std.log.scoped(.runner);

pub const TaskId = u64;

pub const Runner = @This();

io: Io,
next_id: atomic.Value(TaskId),
active: std.AutoHashMap(TaskId, *Task),
loop: Loop,
future: Io.Future(void),
stop: atomic.Value(bool) = .init(false),
queues: MultiMpsc(union(enum) {
    cancelations: Completion,
    completions: Completion,
    timers: Completion,
    submissions: Completion,
}),
chunks: Allocator,
producer: Producer,
waker: AppWaker,
batch: Batch,

pub fn init(
    self: *Runner,
    arena: Allocator,
    chunks: Allocator,
    producer: Producer,
    waker: AppWaker,
    io: std.Io,
) !void {
    self.* = .{
        .waker = waker,
        .producer = producer,
        .chunks = chunks,
        .next_id = .init(0),
        .active = .init(arena),
        .loop = undefined,
        .queues = undefined,
        .io = io,
        .future = undefined,
        .batch = .{},
    };

    self.queues.init();

    try self.active.ensureTotalCapacity(100);
    try self.loop.init(io);

    self.future = try io.concurrent(Runner.run, .{self});
}

pub fn deinit(self: *Runner) void {
    self.stop.store(true, .release);
    _ = self.future.await(self.io);
    self.producer.unregister();
    self.loop.deinit();
}
fn run(self: *Runner) void {
    self._run() catch |err| log.err("Runner err={}", .{err});
}

pub fn _run(self: *Runner) !void {
    while (!self.stop.load(.acquire)) {
        try self.flush();
        try self.loop.run(.no_wait);
        try self.io.sleep(.fromNanoseconds(100), .real);
    }

    try self.flush();
    try self.loop.run(.no_wait);
}

fn flush(self: *@This()) !void {
    if (!self.batch.empty()) {
        try self.producer.push(self.batch, self.io);
        self.batch = .{};
        self.waker.wake();
    }

    while (self.queues.pop(.completions)) |completion| {
        const task: *Task = @fieldParentPtr("completion", completion);
        self.complete(task);
    }

    while (self.queues.pop(.timers)) |completion| {
        const task: *Task = @fieldParentPtr("completion", completion);
        self.submitTimer(task);
    }

    while (self.queues.pop(.submissions)) |completion| {
        const task: *Task = @fieldParentPtr("completion", completion);
        self.submit(task);
    }

    while (self.queues.pop(.cancelations)) |completion| {
        const cancelation: *Runner.Cancelation = @fieldParentPtr("completion", completion);
        const task = self.active.get(cancelation.id) orelse {
            self.chunks.destroy(cancelation);
            continue;
        };

        cancelation.completion.cancel(
            &task.completion,
            struct {
                fn _cancel(c: *Cancelation, _: *Completion) void {
                    c.runner.chunks.destroy(c);
                }
            }._cancel,
            cancelation,
        );
        self.loop.cancel(&cancelation.completion);
    }
}

pub fn @"defer"(
    self: *@This(),
    function: anytype,
    context: anytype,
) TaskId {
    const task = self.new();

    task.@"defer"(function, context);
    self.queues.push(.completions, &task.completion);

    return task.id;
}

pub fn await(
    self: *@This(),
    function: anytype,
    context: anytype,
) !struct { TaskId, Runner.Waker } {
    const task = self.new();
    errdefer self.free(task);

    const waker = try task.await(function, context);

    self.queues.push(.submissions, &task.completion);

    return .{ task.id, waker };
}

pub fn timer(
    self: *@This(),
    function: anytype,
    context: anytype,
    ms: u64,
) !TaskId {
    const task = self.new();

    task.timer(function, context, ms);
    self.queues.push(.timers, &task.completion);

    return task.id;
}

pub fn create(self: *Runner, T: type) !*T {
    return try self.chunks.create(T);
}

pub fn drop(self: *Runner, ptr: anytype) void {
    const T = @typeInfo(@TypeOf(ptr)).pointer.child;

    const TypeErased = struct {
        pub fn destroy(runner: *Runner, _ptr: *anyopaque, res: anyerror!void) bool {
            res catch unreachable;
            const info = TypeInfo.init(T);
            info.deinit(_ptr);
            info.destroy(_ptr, runner.chunks);
            return false;
        }
    };

    _ = self.@"defer"(TypeErased.destroy, .{ self, ptr });
}

pub fn dispatch(self: *Runner, subscription: Receiver, comptime E: type) !*E {
    const chunks = self.chunks;
    const ptr = try chunks.create(E);
    errdefer chunks.destroy(ptr);

    const batched = try chunks.create(Batched);
    batched.* = .{
        .subscription = subscription,
        .type = TypeInfo.init(E),
        .ptr = ptr,
    };

    self.batch.push(batched);

    return ptr;
}

pub fn new(self: *Runner) *Task {
    const context = self.chunks.rawAlloc(MAX_SIZE, MAX_ALIGN, @returnAddress()) orelse
        @panic("Task Context Overflow");

    const task = self.chunks.create(Task) catch @panic("Task Overflow");
    const id = self.next_id.fetchAdd(1, .monotonic);
    task.* = .{ .runner = self, .id = id, .context = context };

    return task;
}

fn add(self: *Runner, task: *Task) void {
    self.active.putAssumeCapacityNoClobber(task.id, task);
}

pub fn complete(self: *Runner, task: *Task) void {
    self.add(task);
    self.loop.complete(&task.completion);
}

pub fn submit(self: *Runner, task: *Task) void {
    self.add(task);
    self.loop.submit(&task.completion);
}

pub fn submitTimer(self: *Runner, task: *Task) void {
    self.add(task);
    self.loop.submit_timer(&task.completion);
}

pub fn cancel(self: *Runner, id: TaskId) void {
    const cancelation = self.chunks.create(Cancelation) catch @panic("Cancel Overflow");
    cancelation.* = .{ .id = id, .runner = self, .completion = .noop };
    self.queues.push(.cancelations, &cancelation.completion);
}

fn destroy(self: *Runner, id: TaskId) void {
    const task = (self.active.fetchRemove(id) orelse @panic("Destroy non-active Task")).value;

    self.free(task);
}

fn free(self: *Runner, task: *Task) void {
    self.chunks.rawFree(
        @as([*]u8, @ptrCast(task.context))[0..MAX_SIZE],
        MAX_ALIGN,
        @returnAddress(),
    );

    self.chunks.destroy(task);
}

pub const Cancelation = struct {
    id: TaskId,
    completion: Completion = .noop,
    runner: *Runner,
};

pub const Task = struct {
    id: TaskId,
    runner: *Runner,
    completion: Completion = .noop,
    context: *anyopaque,

    pub fn destroy(self: *Task) void {
        self.runner.destroy(self.id);
    }

    pub fn assertContext(context: anytype) void {
        const Context = @TypeOf(context);
        const SIZE = @sizeOf(Context);
        const ALIGN = @alignOf(Context);

        if (SIZE > MAX_SIZE or
            ALIGN > MAX_ALIGN.toByteUnits())
        {
            panic("Wrong Context: size: {}, align: {}", .{ SIZE, ALIGN });
        }
    }

    pub fn @"defer"(
        self: *Task,
        function: anytype,
        context: anytype,
    ) void {
        assertContext(context);
        const Context = @TypeOf(context);

        const TypeErased = struct {
            fn complete(task: *Task, _: *Completion, res: Loop.Result) bool {
                const _context: *Context = @ptrCast(@alignCast(task.context));

                const rearm = @call(
                    .always_inline,
                    function,
                    _context.* ++ .{res.@"defer"},
                );

                if (!rearm) task.destroy();

                return rearm;
            }
        };

        const context_ptr: *Context = @ptrCast(@alignCast(self.context));
        context_ptr.* = context;

        self.completion.@"defer"(TypeErased.complete, self);
    }

    pub fn await(
        self: *Task,
        function: anytype,
        context: anytype,
    ) !Waker {
        assertContext(context);
        const Context = @TypeOf(context);

        const TypeErased = struct {
            fn complete(task: *Task, c: *Completion, res: Loop.Result) bool {
                drain(c.operation.machport.port);
                const _context: *Context = @ptrCast(@alignCast(task.context));
                const rearm = @call(.always_inline, function, _context.* ++ .{res.machport});

                if (!rearm) {
                    task.destroy();
                }

                return rearm;
            }
            fn drain(port: posix.system.mach_port_name_t) void {
                var message: struct {
                    header: system.mach_msg_header_t,
                } = undefined;

                while (true) {
                    switch (system.mach_msg(
                        &message.header,
                        .{ .RCV = .{ .TIMEOUT = true } },
                        0,
                        @sizeOf(@TypeOf(message)),
                        port,
                        system.MACH.MSG.TIMEOUT_NONE,
                        system.MACH.PORT.NULL,
                    )) {
                        .RCV_TIMED_OUT => return,
                        .SUCCESS => {},
                        .RCV_TOO_LARGE => {},
                        else => |err| {
                            log.warn("mach msg drain err, may duplicate async wakeups err={}", .{err});
                            return;
                        },
                    }
                }
            }
        };

        const mach_self = system.mach_task_self();
        var mach_port: system.mach_port_name_t = undefined;
        if (system.mach_port_allocate(
            mach_self,
            system.MACH.PORT.RIGHT.RECEIVE,
            &mach_port,
        ) != 0) {
            return error.MachPortAllocFailed;
        }
        errdefer _ = system.mach_port_deallocate(mach_self, mach_port);

        if (system.mach_port_insert_right(
            mach_self,
            mach_port,
            mach_port,
            system.MACH.MSG.TYPE.MAKE_SEND,
        ) != 0) {
            return error.MachPortAllocFailed;
        }

        const mach_port_limits = extern struct { mpl_qlimit: system.natural_t };
        const MACH_PORT_LIMITS_INFO = 1;

        const mach = struct {
            const mach_port_flavor_t = c_int;

            extern "c" fn mach_port_set_attributes(
                task: system.ipc_space_t,
                name: system.mach_port_name_t,
                flavor: mach_port_flavor_t,
                info: *anyopaque,
                count: system.mach_msg_type_number_t,
            ) posix.system.kern_return_t;
        };
        var limits: mach_port_limits = .{ .mpl_qlimit = 1 };
        if (mach.mach_port_set_attributes(
            mach_self,
            mach_port,
            MACH_PORT_LIMITS_INFO,
            &limits,
            @sizeOf(@TypeOf(limits)),
        ) != 0) return error.MachPortAllocFailed;

        const context_ptr: *Context = @ptrCast(@alignCast(self.context));
        context_ptr.* = context;

        self.completion.mach(
            TypeErased.complete,
            self,
            .{ .port = mach_port, .buffer = .{ .array = undefined } },
        );

        return .{ .port = mach_port };
    }

    pub fn timer(
        self: *Task,
        function: anytype,
        context: anytype,
        ms: u64,
    ) void {
        assertContext(context);
        const Context = @TypeOf(context);

        const TypeErased = struct {
            fn complete(task: *Task, _: *Completion, res: Loop.Result) bool {
                const _context: *Context = @ptrCast(@alignCast(task.context));
                const rearm = @call(.always_inline, function, _context.* ++ .{res.timer});

                if (!rearm) {
                    task.destroy();
                }

                return rearm;
            }
        };

        const context_ptr: *Context = @ptrCast(@alignCast(self.context));
        context_ptr.* = context;

        self.completion.timer(TypeErased.complete, self, ms);
    }
};

pub const Waker = struct {
    port: system.mach_port_name_t,

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
            .SEND_INVALID_DEST => |e| {
                log.debug("mach msg err={}", .{e});
            },
            else => |e| {
                log.warn("mach msg err={}", .{e});
                return error.MachMsgFailed;
            },
        }
    }

    pub fn close(self: *const Waker) void {
        _ = system.mach_port_deallocate(
            posix.system.mach_task_self(),
            self.port,
        );
    }
};

test "Task defer allocates and copies context" {
    const gpa = testing.allocator;
    var arena: heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();

    var chunks: ChunkAllocator = undefined;
    try chunks.init(std.testing.allocator, &.{.{ 100, MAX_SIZE }});
    defer chunks.deinit(std.testing.allocator);

    var batches = try App.Batches.init(1, 1, gpa);
    defer batches.deinit(gpa);

    var runner: Runner = undefined;
    try runner.init(arena.allocator(), chunks.allocator(), batches.register().?, .{}, testing.io);
    defer runner.deinit();

    const Context = struct {
        value: u64,
        other: u32,
    };

    var original = Context{ .value = 0x1234_5678_9abc_def0, .other = 0xfeed_beef };
    const task = runner.new();
    runner.add(task);
    defer task.destroy();
    task.@"defer"(struct {
        fn callback(_: Context, res: anyerror!void) bool {
            res catch return false;
            return true;
        }
    }.callback, .{original});

    original = .{ .value = 0, .other = 0 };

    const copied: *const struct { Context } = @ptrCast(@alignCast(task.context));
    try testing.expectEqual(@as(u64, 0x1234_5678_9abc_def0), copied.@"0".value);
    try testing.expectEqual(@as(u32, 0xfeed_beef), copied.@"0".other);
}

test "Task await allocates and copies context" {
    const gpa = testing.allocator;
    var arena: heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();

    var chunks: ChunkAllocator = undefined;
    try chunks.init(std.testing.allocator, &.{.{ 100, MAX_SIZE }});
    defer chunks.deinit(std.testing.allocator);

    var batches = try App.Batches.init(1, 1, gpa);
    defer batches.deinit(gpa);

    var runner: Runner = undefined;
    try runner.init(arena.allocator(), chunks.allocator(), batches.register().?, .{}, testing.io);
    defer runner.deinit();

    const Context = struct {
        value: u64,
        other: u32,
    };

    var original = Context{ .value = 0x1234_5678_9abc_def0, .other = 0xfeed_beef };
    const task = runner.new();
    runner.add(task);
    defer task.destroy();
    const port = try task.await(struct {
        fn callback(_: Context, res: anyerror!void) bool {
            res catch return false;
            return true;
        }
    }.callback, .{original});
    port.close();

    original = .{ .value = 0, .other = 0 };

    const copied: *const struct { Context } = @ptrCast(@alignCast(task.context));
    try testing.expectEqual(@as(u64, 0x1234_5678_9abc_def0), copied.@"0".value);
    try testing.expectEqual(@as(u32, 0xfeed_beef), copied.@"0".other);
}

test "Cancelations" {
    const gpa = testing.allocator;
    var arena: heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();

    var chunks: ChunkAllocator = undefined;
    try chunks.init(std.testing.allocator, &.{.{ 100, MAX_SIZE }});
    defer chunks.deinit(std.testing.allocator);

    var batches = try App.Batches.init(1, 1, gpa);
    defer batches.deinit(gpa);

    var runner: Runner = undefined;
    try runner.init(arena.allocator(), chunks.allocator(), batches.register().?, .{}, testing.io);
    defer runner.deinit();

    const task = runner.new();
    runner.add(task);
    defer task.destroy();
    runner.cancel(task.id);
}
