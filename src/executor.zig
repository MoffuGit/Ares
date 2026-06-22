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
pub const Action = Loop.Action;

pub const ForegroundExecutor = struct {
    worker: Worker,

    pub fn init(self: *ForegroundExecutor, gpa: Allocator, io: Io) !void {
        try self.worker.init(gpa, io);
    }

    pub fn run(self: *ForegroundExecutor) void {
        self.worker.run(.no_wait);
    }

    pub fn deinit(self: *ForegroundExecutor) void {
        self.worker.deinit();
    }

    pub fn @"defer"(self: *ForegroundExecutor, function: anytype, args: anytype) !Handler {
        return try self.worker.@"defer"(function, args);
    }

    pub fn async(
        self: *ForegroundExecutor,
        function: anytype,
        context: anytype,
        buffer: []u8,
    ) !Async {
        return try self.worker.async(function, context, buffer);
    }
};

pub const BackgroundExecutor = struct {
    workers: []Worker,
    stops: []Async,
    next_worker: atomic.Value(usize),
    group: Io.Group,

    pub fn init(self: *BackgroundExecutor, gpa: Allocator, io: Io) !void {
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
                    fn _stop(_worker: *Worker, _: anyerror!void) Action {
                        _worker.stop();
                        return .disarm;
                    }
                }._stop,
                .{work},
                &.{},
            );
            try self.group.concurrent(io, Worker.run, .{ work, .until_done });
        }
    }

    fn worker(self: *BackgroundExecutor) *Worker {
        const index = self.next_worker.fetchAdd(1, .monotonic) % self.workers.len;
        return &self.workers[index];
    }

    pub fn @"defer"(
        self: *BackgroundExecutor,
        function: anytype,
        context: std.meta.ArgsTuple(@TypeOf(function)),
    ) !Handler {
        return try self.worker().@"defer"(function, context);
    }

    pub fn read(
        self: *BackgroundExecutor,
        function: anytype,
        context: anytype,
        data: Loop.Read,
    ) !Handler {
        return try self.worker().read(function, context, data);
    }

    pub fn async(
        self: *BackgroundExecutor,
        function: anytype,
        context: anytype,
        buffer: []u8,
    ) !Async {
        return try self.worker().async(function, context, buffer);
    }

    pub fn deinit(self: *BackgroundExecutor, gpa: Allocator, io: Io) void {
        for (self.stops) |*stop| {
            stop.notifier.notify() catch |err| {
                std.log.err("Error while stopping a worker: {}", .{err});
            };
        }

        self.group.cancel(io);

        for (self.stops) |*stop| {
            stop.handler.drop();
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
    loop: Loop,
    gpa: Allocator,
    id: u32,

    pub fn init(self: *Worker, gpa: Allocator, io: Io) !void {
        self.* = .{
            .gpa = gpa,
            .id = worker_next_id,
            .loop = undefined,
        };

        worker_next_id += 1;
        try self.loop.init(io);
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
    ) !Handler {
        const Context = @TypeOf(context);

        const TypeErased = struct {
            fn complete(task: *Task, _: *Completion, _: Loop.Result) Action {
                var action: Action = .disarm;
                if (!task.canceled()) {
                    const _context: *Context = @ptrCast(@alignCast(task.context.ptr));
                    action = @call(.auto, function, _context.*);
                }

                if (action == .disarm) {
                    task.complete();
                }

                return action;
            }
        };

        const task = try Task.create(self, context);

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
            fn complete(task: *Task, _: *Completion, res: Loop.Result) Action {
                const _context: *Context = @ptrCast(@alignCast(task.context.ptr));
                const action: Action = @call(
                    .auto,
                    function,
                    _context.* ++ .{res.read},
                );
                if (action == .disarm) {
                    task.complete();
                }
                return action;
            }
        };

        const task = try Task.create(self, context);

        try self.loop.read(&task.completion, TypeErased.complete, task, data);
        return .{ .task = task };
    }

    pub fn async(
        self: *Worker,
        function: anytype,
        context: anytype,
        buffer: []u8,
    ) !Async {
        const Context = @TypeOf(context);

        const TypeErased = struct {
            fn complete(task: *Task, c: *Completion, res: Loop.Result) Action {
                drain(c.operation.machport.port);
                const _context: *Context = @ptrCast(@alignCast(task.context.ptr));
                const action: Action = @call(
                    .auto,
                    function,
                    _context.* ++ .{res.machport},
                );

                _ = system.mach_port_deallocate(
                    posix.system.mach_task_self(),
                    c.operation.machport.port,
                );

                if (action == .disarm) {
                    task.complete();
                }

                return action;
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

        const task = try Task.create(self, context);

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
        const mach = struct {
            extern fn mach_port_set_attributes(
                task: system.ipc_space_t,
                name: system.mach_port_name_t,
                flavor: system.natural_t,
                port_info: *system.integer_t,
                port_infoCnt: system.mach_msg_type_number_t,
            ) system.kern_return_t;
        };
        var limits: mach_port_limits = .{ .mpl_qlimit = 1 };
        if (mach.mach_port_set_attributes(
            mach_self,
            mach_port,
            1,
            @ptrCast(&limits),
            @sizeOf(@TypeOf(limits)) / @sizeOf(system.natural_t),
        ) != 0) return error.MachPortAllocFailed;
        self.loop.mach(&task.completion, TypeErased.complete, task, .{ .port = mach_port, .buffer = buffer });
        return .{ .handler = .{ .task = task }, .notifier = .{ .port = mach_port } };
    }

    pub fn deinit(self: *Worker) void {
        self.loop.deinit();
    }
};

const State = packed struct(u8) {
    handler: bool = false,
    canceled: bool = false,
    completed: bool = false,
    refs: u5 = 0,
};

pub const Task = struct {
    completion: Completion,
    cancelation: Completion,
    worker: *Worker,
    context: []u8,
    alignment: u8,

    state: atomic.Value(State) = .init(.{ .handler = true, .refs = 1 }),

    fn create(worker: *Worker, context: anytype) !*Task {
        const Context = @TypeOf(context);

        const task = try worker.gpa.create(Task);
        errdefer worker.gpa.destroy(task);

        const copy = try worker.gpa.create(Context);
        errdefer worker.gpa.destroy(copy);
        copy.* = context;

        task.* = .{
            .completion = .noop,
            .cancelation = .noop,
            .worker = worker,
            .context = @ptrCast(copy),
            .alignment = @alignOf(Context),
        };

        return task;
    }

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
                fn cancel(task: *Task, _: *Completion, _: Loop.Result) Action {
                    task.release();
                    return .disarm;
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
        const gpa = self.worker.gpa;
        gpa.rawFree(self.context, .fromByteUnits(self.alignment), @returnAddress());
        gpa.destroy(self);
    }
};

pub const Handler = struct {
    task: *Task,

    pub fn cancel(self: *Handler) void {
        self.task.cancel();
    }

    pub fn detach(self: *const Handler) void {
        self.task.releaseHandler();
    }

    pub fn drop(self: *Handler) void {
        self.task.cancel();
    }
};

pub const Async = struct {
    handler: Handler,
    notifier: Notifier,
};

pub const Notifier = struct {
    port: system.mach_port_name_t,

    pub fn notify(self: *Notifier) !void {
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
            .{ .SEND = .{ .TIMEOUT = true } },
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

fn testDeferTask(calls: *u32) Action {
    calls.* += 1;
    return .disarm;
}

fn testReadTask(calls: *u32, bytes_read: *usize, result: anyerror!usize) Action {
    calls.* += 1;
    bytes_read.* = result catch 0;
    return .disarm;
}

fn testMachTask(calls: *u32, result: anyerror!void) Action {
    if (result != error.Canceled) {
        calls.* += 1;
    }

    return .disarm;
}

test "task completes and stays alive until handler detaches" {
    const gpa = testing.allocator;
    const io = testing.io;

    var worker: Worker = undefined;
    try worker.init(gpa, io);
    defer worker.deinit();

    var calls: u32 = 0;

    var handler = try worker.@"defer"(testDeferTask, .{&calls});

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
            .buffer = &buffer,
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
    var buffer: [32]u8 = undefined;

    var async = try worker.async(testMachTask, .{&calls}, &buffer);

    worker.run(.no_wait);
    try testing.expectEqual(@as(u32, 0), calls);

    try async.notifier.notify();
    try async.notifier.notify();
    try async.notifier.notify();
    try async.notifier.notify();
    try async.notifier.notify();
    try async.notifier.notify();
    try async.notifier.notify();
    worker.run(.until_done);

    try testing.expectEqual(@as(u32, 1), calls);

    async.handler.drop();
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

    var handler = try worker.@"defer"(testDeferTask, .{&calls});
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

    var handler = try worker.@"defer"(testDeferTask, .{&calls});
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

    var handler = try worker.@"defer"(testDeferTask, .{&calls});
    handler.detach();

    worker.run(.until_done);

    try testing.expectEqual(@as(u32, 1), calls);
}
