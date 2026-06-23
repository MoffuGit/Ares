const std = @import("std");
const heap = std.heap;
const Allocator = std.mem.Allocator;
const Io = std.Io;
const testing = std.testing;
const debug = std.debug;
const atomic = std.atomic;
const posix = std.posix;
const system = posix.system;

const Loop = @import("loop.zig");
const Completion = Loop.Completion;

pub const ForegroundExecutor = struct {
    worker: Worker,

    pub fn init(self: *@This(), gpa: Allocator, io: Io) !void {
        try self.worker.init(gpa, io);
    }

    pub fn run(self: *@This()) void {
        self.worker.run(.no_wait);
    }

    pub fn deinit(self: *@This()) void {
        self.worker.deinit();
    }

    pub fn @"defer"(self: *@This(), function: anytype, args: anytype) Handler {
        return self.worker.@"defer"(function, args);
    }

    pub fn async(self: *@This(), function: anytype, context: anytype) !Async {
        return try self.worker.async(function, context);
    }
};

pub const BackgroundExecutor = struct {
    workers: []Worker,
    stops: []Async,
    next_worker: atomic.Value(usize),
    group: Io.Group,

    pub fn init(self: *@This(), gpa: Allocator, io: Io) !void {
        const cpu_count = try std.Thread.getCpuCount();

        const workers = try gpa.alloc(Worker, cpu_count);
        errdefer gpa.free(workers);

        const stops = try gpa.alloc(Async, cpu_count);
        errdefer gpa.free(stops);

        self.* = .{
            .workers = workers,
            .stops = stops,
            .next_worker = .init(0),
            .group = .init,
        };

        for (self.workers, self.stops) |*work, *stop| {
            try work.init(gpa, io);
            stop.* = try work.async(
                struct {
                    fn _stop(_worker: *Worker, _: anyerror!void) bool {
                        _worker.stop();
                        return false;
                    }
                }._stop,
                .{work},
            );
            try self.group.concurrent(io, Worker.run, .{ work, .until_done });
        }
    }

    fn worker(self: *@This()) *Worker {
        const index = self.next_worker.fetchAdd(1, .monotonic) % self.workers.len;
        return &self.workers[index];
    }

    pub fn @"defer"(
        self: *@This(),
        function: anytype,
        context: std.meta.ArgsTuple(@TypeOf(function)),
    ) !Handler {
        return try self.worker().@"defer"(function, context);
    }

    pub fn read(
        self: *@This(),
        function: anytype,
        context: anytype,
        data: Loop.Read,
    ) !Handler {
        return try self.worker().read(function, context, data);
    }

    pub fn async(
        self: *@This(),
        function: anytype,
        context: anytype,
        buffer: []u8,
    ) !Async {
        return try self.worker().async(function, context, buffer);
    }

    pub fn deinit(self: *@This(), gpa: Allocator, io: Io) void {
        for (self.stops) |stop| {
            const notifier = stop.@"1";
            notifier.notify() catch |err| {
                std.log.err("Error while stopping a worker: {}", .{err});
            };
        }

        self.group.cancel(io);

        for (self.stops) |*stop| {
            stop.@"0".drop();
        }

        for (self.workers) |*work| {
            work.deinit();
        }

        gpa.free(self.stops);
        gpa.free(self.workers);
    }
};

var worker_next_id: u32 = 0;

const Worker = struct {
    pool: heap.MemoryPool(Task),
    mutex: Io.Mutex,
    gpa: Allocator,
    loop: Loop,
    id: u32,
    io: Io,

    pub fn init(self: *Worker, gpa: Allocator, io: Io) !void {
        self.* = .{
            .gpa = gpa,
            .io = io,
            .id = worker_next_id,
            .loop = undefined,
            .mutex = .init,
            .pool = try .initCapacity(gpa, 100),
        };
        worker_next_id += 1;
        try self.loop.init(io);
    }

    pub fn deinit(self: *Worker) void {
        self.loop.deinit();
        self.pool.deinit(self.gpa);
    }

    pub fn new(self: *Worker, context: anytype) *Task {
        const Context = @TypeOf(context);

        if (@sizeOf(Context) > Task.max_context_size or @alignOf(Context) > Task.max_context_alignment) {
            @compileError("executor task context has incorrect size or aligment");
        }

        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        const task = self.pool.create(self.gpa) catch {
            @panic("Worker Tasks Overflow");
        };

        task.* = .{
            .completion = .noop,
            .cancelation = .noop,
            .worker = self,
            .context = undefined,
        };
        @as(*Context, @ptrCast(@alignCast(&task.context))).* = context;

        return task;
    }

    pub fn destroy(self: *Worker, task: *Task) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        self.pool.destroy(task);
    }

    pub fn run(self: *Worker, mode: Loop.RunMode) void {
        self.loop.run(mode) catch |err| {
            debug.panic("Worker {} loop err: {}", .{ self.id, err });
        };
    }

    fn stop(worker: *Worker) void {
        worker.loop.stop();
    }

    pub fn @"defer"(
        self: *Worker,
        function: anytype,
        context: std.meta.ArgsTuple(@TypeOf(function)),
    ) Handler {
        const Context = @TypeOf(context);

        const TypeErased = struct {
            fn complete(task: *Task, _: *Completion, _: Loop.Result) bool {
                if (task.canceled()) return false;

                const _context: *Context = @ptrCast(@alignCast(&task.context));
                const rearm = @call(.auto, function, _context.*);

                if (!rearm) task.complete();

                return rearm;
            }
        };

        const task = self.new(context);

        self.loop.@"defer"(&task.completion, TypeErased.complete, task);
        return .{ .task = task };
    }

    pub fn read(
        self: *Worker,
        function: anytype,
        context: anytype,
        data: Loop.Read,
    ) !Handler {
        const Context = @TypeOf(context);

        const TypeErased = struct {
            fn complete(task: *Task, _: *Completion, res: Loop.Result) bool {
                const _context: *Context = @ptrCast(@alignCast(&task.context));
                const rearm = @call(
                    .auto,
                    function,
                    _context.* ++ .{res.read},
                );
                if (!rearm) task.complete();

                return rearm;
            }
        };

        const task = self.new(context);

        try self.loop.read(&task.completion, TypeErased.complete, task, data);
        return .{ .task = task };
    }

    pub fn async(
        self: *Worker,
        function: anytype,
        context: anytype,
    ) !Async {
        const Context = @TypeOf(context);

        const TypeErased = struct {
            fn complete(task: *Task, c: *Completion, res: Loop.Result) bool {
                drain(c.operation.machport.port);
                const _context: *Context = @ptrCast(@alignCast(&task.context));
                const rearm = @call(
                    .auto,
                    function,
                    _context.* ++ .{res.machport},
                );

                if (!rearm) {
                    _ = system.mach_port_deallocate(
                        posix.system.mach_task_self(),
                        c.operation.machport.port,
                    );

                    task.complete();
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
                            std.log.warn("mach msg drain err, may duplicate async wakeups err={}", .{err});
                            return;
                        },
                    }
                }
            }
        };

        const task = self.new(context);

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
        self.loop.mach(&task.completion, TypeErased.complete, task, .{ .port = mach_port, .buffer = .{ .array = undefined } });
        return .{ .{ .task = task }, .{ .port = mach_port } };
    }
};

const State = packed struct(u8) {
    handler: bool = false,
    canceled: bool = false,
    completed: bool = false,
    refs: u5 = 0,
};

pub const Task = struct {
    const max_context_size = 128;
    const max_context_alignment = 16;

    completion: Completion,
    cancelation: Completion,
    context: [max_context_size]u8 align(max_context_alignment),
    worker: *Worker,

    state: atomic.Value(State) = .init(.{ .handler = true, .refs = 1 }),

    fn cancel(self: *Task) void {
        var old = self.state.load(.acquire);
        while (true) {
            if (old.completed == true and old.refs == 0) {
                return self.destroy();
            }

            var new = old;
            new.canceled = true;
            new.refs += 1;
            new.handler = false;

            old = self.state.cmpxchgWeak(old, new, .release, .acquire) orelse break;
        }

        self.worker.loop.cancel(
            &self.cancelation,
            &self.completion,
            struct {
                fn cancel(task: *Task, _: *Completion, _: Loop.Result) void {
                    task.release();
                }
            }.cancel,
            self,
        );
    }

    fn complete(self: *Task) void {
        var old = self.state.load(.acquire);
        while (true) {
            debug.assert(old.refs > 0);

            var new = old;
            new.refs -= 1;
            new.completed = true;

            old = self.state.cmpxchgWeak(old, new, .acq_rel, .acquire) orelse break;
        }

        if (old.refs == 1 and !old.handler) self.destroy();
    }

    fn release(self: *Task) void {
        var old = self.state.load(.acquire);
        while (true) {
            debug.assert(old.refs > 0);

            var new = old;
            new.refs -= 1;

            old = self.state.cmpxchgWeak(old, new, .acq_rel, .acquire) orelse break;
        }

        if (old.refs == 1 and !old.handler) self.destroy();
    }

    fn releaseHandler(self: *Task) void {
        var old = self.state.load(.acquire);
        while (true) {
            if (!old.handler) return;

            var new = old;
            new.handler = false;

            old = self.state.cmpxchgWeak(old, new, .acq_rel, .acquire) orelse break;
        }

        if (old.refs == 1 and !old.handler) self.destroy();
    }

    fn canceled(self: *Task) bool {
        return self.state.load(.acquire).canceled;
    }

    fn destroy(self: *Task) void {
        self.worker.destroy(self);
    }
};

pub const Handler = struct {
    task: *Task,

    pub fn cancel(self: *const Handler) void {
        self.task.cancel();
    }

    pub fn detach(self: *const Handler) void {
        self.task.releaseHandler();
    }

    pub fn drop(self: *const Handler) void {
        self.task.cancel();
    }
};

pub const Async = struct { Handler, Notifier };

pub const Notifier = struct {
    port: system.mach_port_name_t,

    pub fn notify(self: *const Notifier) !void {
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
};

fn testDeferTask(calls: *u32) bool {
    calls.* += 1;
    return false;
}

fn testReadTask(calls: *u32, bytes_read: *usize, result: anyerror!usize) bool {
    calls.* += 1;
    bytes_read.* = result catch 0;
    return false;
}

fn testMachTask(calls: *u32, result: anyerror!void) bool {
    if (result != error.Canceled) {
        calls.* += 1;
    }

    return false;
}

test "task completes and stays alive until handler detaches" {
    const gpa = testing.allocator;
    const io = testing.io;

    var worker: Worker = undefined;
    try worker.init(gpa, io);
    defer worker.deinit();

    var calls: u32 = 0;

    var handler = worker.@"defer"(testDeferTask, .{&calls});

    worker.run(.until_done);

    try testing.expectEqual(@as(u32, 1), calls);

    handler.drop();

    worker.run(.until_done);

    try testing.expectEqual(@as(u32, 1), calls);
}

test "read task completes and stays alive until handler detaches" {
    const gpa = testing.allocator;
    const io = testing.io;

    var worker: Worker = undefined;
    try worker.init(gpa, io);
    defer worker.deinit();

    const contents = "hello from executor";
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const file = try tmp.dir.createFile(io, "read.txt", .{ .read = true });
    defer file.close(io);
    try file.writeStreamingAll(io, contents);
    try testing.expectEqual(@as(i64, 0), std.posix.system.lseek(file.handle, 0, std.posix.SEEK.SET));

    var buffer: [contents.len]u8 = undefined;
    var calls: u32 = 0;
    var bytes_read: usize = 0;

    var handler = try worker.read(
        testReadTask,
        .{ &calls, &bytes_read },
        .{
            .fd = file.handle,
            .buffer = .{ .slice = &buffer },
        },
    );

    worker.run(.until_done);

    try testing.expectEqual(@as(u32, 1), calls);
    try testing.expectEqual(contents.len, bytes_read);
    try testing.expectEqualStrings(contents, &buffer);

    handler.drop();
    worker.run(.until_done);

    try testing.expectEqual(@as(u32, 1), calls);
}

test "Async notifier completes task" {
    const gpa = testing.allocator;
    const io = testing.io;

    var worker: Worker = undefined;
    try worker.init(gpa, io);
    defer worker.deinit();

    var calls: u32 = 0;

    const handler, const notifier = try worker.async(testMachTask, .{&calls});

    worker.run(.no_wait);
    try testing.expectEqual(@as(u32, 0), calls);

    try notifier.notify();
    try notifier.notify();
    try notifier.notify();
    try notifier.notify();
    try notifier.notify();
    try notifier.notify();
    try notifier.notify();
    worker.run(.until_done);

    try testing.expectEqual(@as(u32, 1), calls);

    handler.drop();
    worker.run(.until_done);

    try testing.expectEqual(@as(u32, 1), calls);
}

test "task can cancel" {
    const gpa = testing.allocator;
    const io = testing.io;

    var worker: Worker = undefined;
    try worker.init(gpa, io);
    defer worker.deinit();

    var calls: u32 = 0;

    var handler = worker.@"defer"(testDeferTask, .{&calls});
    handler.cancel();

    worker.run(.until_done);

    try testing.expectEqual(@as(u32, 0), calls);
}

test "dropping handler cancels pending task" {
    const gpa = testing.allocator;
    const io = testing.io;

    var worker: Worker = undefined;
    try worker.init(gpa, io);
    defer worker.deinit();

    var calls: u32 = 0;

    var handler = worker.@"defer"(testDeferTask, .{&calls});
    handler.drop();

    worker.run(.until_done);

    try testing.expectEqual(@as(u32, 0), calls);
}

test "task can detach" {
    const gpa = testing.allocator;
    const io = testing.io;

    var worker: Worker = undefined;
    try worker.init(gpa, io);
    defer worker.deinit();

    var calls: u32 = 0;

    var handler = worker.@"defer"(testDeferTask, .{&calls});
    handler.detach();

    worker.run(.until_done);

    try testing.expectEqual(@as(u32, 1), calls);
}
