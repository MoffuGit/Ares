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
const Operation = Loop.Operation;
pub const Read = Loop.Read;

pub const Executor = struct {
    stops: []Await,
    workers: []Worker,
    next_worker: atomic.Value(u8),

    groups: heap.MemoryPool(Group),
    mutex: Io.Mutex,
    threads: Io.Group,
    io: Io,

    arena: Allocator,
    gpa: Allocator,

    pub fn init(self: *@This(), arena: Allocator, gpa: Allocator, io: Io) !void {
        const cpu_count = try std.Thread.getCpuCount();

        const workers = try arena.alloc(Worker, cpu_count);
        const stops = try arena.alloc(Await, cpu_count);

        self.* = .{
            .gpa = gpa,
            .workers = workers,
            .stops = stops,
            .next_worker = .init(0),
            .groups = .empty,
            .mutex = .init,
            .arena = arena,
            .io = io,
            .threads = .init,
        };

        for (self.workers, self.stops) |*work, *stop| {
            try work.init(arena, io);
            stop.* = try work.await(
                Worker.stop,
                .{work},
            );
            try self.threads.concurrent(io, Worker.run, .{ work, .until_done });
        }
    }

    fn worker(self: *@This()) *Worker {
        const index = self.next_worker.fetchAdd(1, .monotonic) % self.workers.len;
        return &self.workers[index];
    }

    pub fn @"defer"(
        self: *@This(),
        function: anytype,
        context: anytype,
    ) Handler {
        return self.worker().@"defer"(function, context);
    }

    pub fn read(
        self: *@This(),
        function: anytype,
        context: anytype,
        data: Read,
    ) !Handler {
        return try self.worker().read(function, context, data);
    }

    pub fn concurrent(
        self: *@This(),
        function: anytype,
        context: anytype,
        comptime op_tag: std.meta.Tag(Operation),
        op_data: @FieldType(Operation, @tagName(op_tag)),
        resolver: anytype,
    ) !Handler {
        return try self.worker().concurrent(function, context, op_tag, op_data, resolver);
    }

    pub fn await(
        self: *@This(),
        function: anytype,
        context: anytype,
    ) !Await {
        return try self.worker().await(function, context);
    }

    pub fn group(self: *@This()) *Group {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        const result = self.groups.create(self.arena) catch {
            @panic("BackgroundExecutor Groups Overflow");
        };
        result.* = Group.init(self);
        return result;
    }

    fn reclaimGroup(self: *@This(), _group: *Group) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        self.groups.destroy(_group);
    }

    pub fn deinit(self: *@This()) void {
        for (self.stops) |stop| {
            const notifier = stop.@"1";
            notifier.wake() catch |err| {
                std.log.err("Error while stopping a worker: {}", .{err});
            };
        }

        self.threads.cancel(self.io);

        for (self.stops) |*stop| {
            stop.@"0".cancel();
        }

        for (self.workers) |*work| {
            work.deinit();
        }
    }
};

pub const Worker = struct {
    pool: heap.MemoryPool(Task),
    mutex: Io.Mutex,
    arena: Allocator,
    loop: Loop,
    io: Io,

    pub fn init(self: *Worker, arena: Allocator, io: Io) !void {
        self.* = .{
            .arena = arena,
            .io = io,
            .loop = undefined,
            .mutex = .init,
            .pool = .empty,
        };
        try self.loop.init(io);
    }

    pub fn deinit(self: *Worker) void {
        self.loop.deinit();
    }

    pub fn new(self: *Worker, context: anytype) *Task {
        const Context = @TypeOf(context);

        if (@sizeOf(Context) > Task.max_context_size or @alignOf(Context) > Task.max_context_alignment) {
            @compileError("executor task context has incorrect size or aligment");
        }

        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        const task = self.pool.create(self.arena) catch {
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
            debug.panic("Worker  err: {}", .{err});
        };
    }

    fn stop(self: *Worker, _: anyerror!void) bool {
        self.loop.stop();
        self.loop.group.cancel(self.io);

        return false;
    }

    pub fn @"defer"(
        self: *Worker,
        function: anytype,
        context: anytype,
    ) Handler {
        const Context = @TypeOf(context);

        const TypeErased = struct {
            fn complete(task: *Task, _: *Completion, res: Loop.Result) bool {
                const _context: *Context = @ptrCast(@alignCast(&task.context));
                const rearm = @call(.auto, function, _context.* ++ .{res.@"defer"});

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
    ) Handler {
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

        self.loop.read(&task.completion, TypeErased.complete, task, data);
        return .{ .task = task };
    }

    pub fn concurrent(
        self: *Worker,
        function: anytype,
        context: anytype,
    ) Handler {
        const Context = @TypeOf(context);

        const TypeErased = struct {
            fn complete(task: *Task, _: *Completion) bool {
                const _context: *Context = @ptrCast(@alignCast(&task.context));
                const rearm = @call(
                    .auto,
                    function,
                    _context.*,
                );
                if (!rearm) task.complete();

                return rearm;
            }
        };

        const task = self.new(context);

        self.loop.concurrent(
            &task.completion,
            TypeErased.complete,
            task,
        );
        return .{ .task = task };
    }

    pub fn await(
        self: *Worker,
        function: anytype,
        context: anytype,
    ) !Await {
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

pub const Task = struct {
    const max_context_size = 128;
    const max_context_alignment = 16;

    const State = packed struct(u8) {
        handler: bool = false,
        canceled: bool = false,
        completed: bool = false,
        refs: u5 = 0,
    };

    completion: Completion,
    cancelation: Completion,
    context: [max_context_size]u8 align(max_context_alignment),
    worker: *Worker,

    state: atomic.Value(State) = .init(.{ .handler = true, .refs = 1 }),

    fn cancel(self: *Task) void {
        var old = self.state.load(.acquire);
        while (true) {
            if (old.canceled) return;

            var new = old;
            new.handler = false;
            new.canceled = true;
            if (!old.completed) new.refs += 1;

            old = self.state.cmpxchgWeak(old, new, .acq_rel, .acquire) orelse break;
        }

        if (old.completed) {
            if (old.refs == 0 and !old.handler) self.destroy();
            return;
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

        if (old.refs == 0 and !old.handler) self.destroy();
    }

    fn completed(self: *Task) bool {
        return self.state.load(.acquire).completed;
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

    pub fn detach(self: *const Handler) void {
        self.task.releaseHandler();
    }

    pub fn cancel(self: *const Handler) void {
        self.task.cancel();
    }

    pub fn worker(self: *const Handler) *Worker {
        return self.task.worker;
    }
};

pub const Group = struct {
    const State = enum(u8) { open, closing, drained };
    const Node = struct {
        handler: Handler,
        next: ?*Node = null,
    };

    executor: *Executor,
    pending: atomic.Value(usize),
    state: atomic.Value(State),
    alloc: heap.ArenaAllocator,
    handlers: ?*Node,
    io: Io,
    mutex: Io.Mutex,

    pub fn init(executor: *Executor) Group {
        return .{
            .io = executor.io,
            .mutex = .init,
            .executor = executor,
            .pending = .init(0),
            .state = .init(.open),
            //BUG:
            //this is wrong and acc a lot of memory
            .alloc = .init(executor.arena),
            .handlers = null,
        };
    }

    pub fn arena(self: *Group) Allocator {
        return self.alloc.allocator();
    }

    pub fn @"defer"(
        self: *Group,
        function: anytype,
        context: anytype,
    ) void {
        const Context = @TypeOf(context);
        const Wrapper = struct {
            fn complete(group: *Group, user_context: Context, res: anyerror!void) bool {
                const rearm = @call(.auto, function, user_context ++ .{ group, res });
                if (!rearm) group.finishTask();
                return rearm;
            }
        };

        _ = self.pending.fetchAdd(1, .monotonic);

        const worker = self.executor.worker();
        const handler = worker.@"defer"(Wrapper.complete, .{ self, context });
        self.join(handler);
    }

    pub fn await(
        self: *Group,
        function: anytype,
        context: anytype,
    ) !Waker {
        const Context = @TypeOf(context);
        const Wrapper = struct {
            group: *Group,
            user_context: Context,

            fn complete(group: *Group, user_context: Context, result: anyerror!void) bool {
                const rearm = @call(.auto, function, user_context ++ .{ group, result });
                if (!rearm) group.finishTask();
                return rearm;
            }
        };

        const worker = self.executor.worker();

        _ = self.pending.fetchAdd(1, .monotonic);

        const handler, const waker = try worker.await(Wrapper.complete, .{ self, context });
        self.join(handler);
        return waker;
    }

    pub fn concurrent(
        self: *Group,
        function: anytype,
        context: anytype,
    ) void {
        const Context = @TypeOf(context);
        const Wrapper = struct {
            fn complete(group: *Group, user_context: Context) bool {
                const rearm = @call(.auto, function, user_context ++ .{group});
                if (!rearm) group.finishTask();
                return rearm;
            }
        };

        _ = self.pending.fetchAdd(1, .monotonic);

        const worker = self.executor.worker();
        const handler = worker.concurrent(
            Wrapper.complete,
            .{ self, context },
        );
        self.join(handler);
    }

    pub fn close(self: *Group) void {
        var node = self.handlers;
        self.handlers = null;
        while (node) |current| : (node = current.next) {
            current.handler.detach();
        }

        self.state.store(.closing, .release);
        if (self.pending.load(.acquire) == 0) self.deinit();
    }

    pub fn cancel(self: *Group) void {
        var node = self.handlers;
        self.handlers = null;
        while (node) |current| : (node = current.next) {
            current.handler.cancel();
        }

        self.state.store(.closing, .release);
        if (self.pending.load(.acquire) == 0) self.deinit();
    }

    pub fn closing(self: *Group) bool {
        return self.state.load(.acquire) != .open;
    }

    fn join(self: *Group, handler: Handler) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        const node = self.alloc.allocator().create(Node) catch {
            @panic("BackgroundExecutor Group Handlers Overflow");
        };
        node.* = .{ .handler = handler, .next = self.handlers };
        self.handlers = node;
    }

    fn finishTask(self: *Group) void {
        const old = self.pending.fetchSub(1, .acq_rel);
        debug.assert(old > 0);

        if (old == 1 and self.state.load(.acquire) == .closing) {
            return self.deinit();
        }
    }

    fn deinit(self: *Group) void {
        if (self.state.swap(.drained, .acq_rel) == .drained) return;

        self.alloc.deinit();

        self.executor.reclaimGroup(self);
    }
};

pub const Await = struct { Handler, Waker };

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
            else => |e| {
                std.log.warn("mach msg err={}", .{e});
                return error.MachMsgFailed;
            },
        }
    }
};

fn testDeferTask(calls: *u32, result: anyerror!void) bool {
    result catch return false;
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

fn testGroupConcurrentResolve(_: void) Loop.Result {
    return .{ .@"defer" = {} };
}

test "task completes and stays alive until handler detaches" {
    const gpa = testing.allocator;
    const io = testing.io;

    var alloc = heap.ArenaAllocator.init(gpa);
    defer alloc.deinit();

    const arena = alloc.allocator();

    var worker: Worker = undefined;
    try worker.init(arena, io);
    defer worker.deinit();

    var calls: u32 = 0;

    var handler = worker.@"defer"(testDeferTask, .{&calls});

    worker.run(.until_done);

    try testing.expectEqual(@as(u32, 1), calls);

    handler.cancel();

    worker.run(.until_done);

    try testing.expectEqual(@as(u32, 1), calls);
}

test "read task completes and stays alive until handler detaches" {
    const gpa = testing.allocator;
    const io = testing.io;

    var alloc = heap.ArenaAllocator.init(gpa);
    defer alloc.deinit();

    const arena = alloc.allocator();

    var worker: Worker = undefined;
    try worker.init(arena, io);
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

    var handler = worker.read(
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

    handler.cancel();
    worker.run(.until_done);

    try testing.expectEqual(@as(u32, 1), calls);
}

test "Async notifier completes task" {
    const gpa = testing.allocator;
    const io = testing.io;

    var alloc = heap.ArenaAllocator.init(gpa);
    defer alloc.deinit();

    const arena = alloc.allocator();

    var worker: Worker = undefined;
    try worker.init(arena, io);
    defer worker.deinit();

    var calls: u32 = 0;

    const handler, const notifier = try worker.await(testMachTask, .{&calls});

    worker.run(.no_wait);
    try testing.expectEqual(@as(u32, 0), calls);

    try notifier.wake();
    try notifier.wake();
    try notifier.wake();
    try notifier.wake();
    try notifier.wake();
    try notifier.wake();
    try notifier.wake();
    worker.run(.until_done);

    try testing.expectEqual(@as(u32, 1), calls);

    handler.cancel();
    worker.run(.until_done);

    try testing.expectEqual(@as(u32, 1), calls);
}

test "dropping handler cancels pending task" {
    const gpa = testing.allocator;
    const io = testing.io;

    var alloc = heap.ArenaAllocator.init(gpa);
    defer alloc.deinit();

    const arena = alloc.allocator();

    var worker: Worker = undefined;
    try worker.init(arena, io);
    defer worker.deinit();

    var calls: u32 = 0;

    var handler = worker.@"defer"(testDeferTask, .{&calls});
    handler.cancel();

    worker.run(.until_done);

    try testing.expectEqual(@as(u32, 0), calls);
}

test "task can detach" {
    const gpa = testing.allocator;
    const io = testing.io;

    var alloc = heap.ArenaAllocator.init(gpa);
    defer alloc.deinit();

    const arena = alloc.allocator();

    var worker: Worker = undefined;
    try worker.init(arena, io);
    defer worker.deinit();

    var calls: u32 = 0;

    var handler = worker.@"defer"(testDeferTask, .{&calls});
    handler.detach();

    worker.run(.until_done);

    try testing.expectEqual(@as(u32, 1), calls);
}

fn testDeferTaskGroup(calls: *u32, _: *Group, result: anyerror!void) bool {
    result catch return false;
    calls.* += 1;
    return false;
}

test "group defer completes" {
    const gpa = testing.allocator;
    const io = testing.io;

    var alloc = heap.ArenaAllocator.init(gpa);
    defer alloc.deinit();

    const arena = alloc.allocator();

    var executor: Executor = undefined;
    try executor.init(arena, gpa, io);
    defer executor.deinit();

    var calls: u32 = 0;
    const group = executor.group();

    group.@"defer"(testDeferTaskGroup, .{&calls});
    group.close();

    try io.sleep(.fromMilliseconds(10), .real);

    try testing.expectEqual(@as(u32, 1), calls);
}

fn testConcurrentTaskGroup(calls: *u32, _: *Group) bool {
    calls.* += 1;
    return false;
}

test "group concurrent completes" {
    const gpa = testing.allocator;
    const io = testing.io;

    var alloc = heap.ArenaAllocator.init(gpa);
    defer alloc.deinit();

    const arena = alloc.allocator();

    var executor: Executor = undefined;
    try executor.init(arena, gpa, io);
    defer executor.deinit();

    var calls: u32 = 0;
    const group = executor.group();

    group.concurrent(
        testConcurrentTaskGroup,
        .{&calls},
    );
    group.close();

    try io.sleep(.fromMilliseconds(10), .real);

    try testing.expectEqual(@as(u32, 1), calls);
}
