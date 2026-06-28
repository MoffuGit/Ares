const std = @import("std");
const heap = std.heap;
const Allocator = std.mem.Allocator;
const Io = std.Io;
const testing = std.testing;
const debug = std.debug;
const posix = std.posix;
const builtin = @import("builtin");
const system = posix.system;
const assert = debug.assert;

const Loop = @import("loop.zig");
const Completion = Loop.Completion;
const Operation = Loop.Operation;
pub const Read = Loop.Read;
const datastruct = @import("datastruct.zig");
const slotmap = datastruct.slotmap;

const TaskId = slotmap.Key;

pub const Scheduler = struct {
    arena: Allocator,
    loop: Loop,
    pool: std.heap.MemoryPool(Task),
    active: slotmap.SlotMap(*Task),

    pub fn init(self: *Scheduler, arena: Allocator, io: Io) !void {
        self.* = .{
            .arena = arena,
            .loop = undefined,
            .pool = undefined,
            .active = undefined,
        };
        self.pool = try .initCapacity(arena, 100);
        self.active = try .init(arena, 100);

        try self.loop.init(io);
    }

    pub fn deinit(self: *Scheduler) void {
        self.loop.deinit();
    }

    pub fn new(self: *Scheduler) *Task {
        const task = self.pool.create(undefined) catch @panic("Task allocation failed");
        task.* = .{
            .id = null,
            .completion = .noop,
            .cancelation = .noop,
            .scheduler = self,
            .context = undefined,
        };

        return task;
    }

    fn destroy(self: *Scheduler, id: TaskId) void {
        const task = self.active.remove(id) orelse @panic("Destroy call on non-active Task");
        self.pool.destroy(task);
    }

    pub fn complete(self: *Scheduler, task: *Task) Cancelation {
        assert(task.completion.state == .idle);
        assert(task.id == null);

        const id = self.active.put(task) catch @panic("Task Overflow");
        task.id = id;

        self.loop.complete(&task.completion);

        return .{ .id = id, .scheduler = self };
    }

    pub fn submit(self: *Scheduler, task: *Task) Cancelation {
        assert(task.completion.state == .idle);
        assert(task.id == null);

        const id = self.active.put(task) catch @panic("Task Overflow");
        task.id = id;

        self.loop.submit(&task.completion);

        return .{ .id = id, .scheduler = self };
    }

    fn cancel(self: *Scheduler, id: TaskId) void {
        const task = (self.active.get(id) orelse return).*;

        self.loop.cancel(
            &task.cancelation,
            &task.completion,
            struct {
                fn cancel(_: *Task, _: *Completion) void {}
            }.cancel,
            task,
        );
    }

    pub fn run(self: *Scheduler, mode: Loop.RunMode) void {
        self.loop.run(mode) catch |err| {
            debug.panic("Worker  err: {}", .{err});
        };
    }

    pub fn @"defer"(
        self: *Scheduler,
        function: anytype,
        context: anytype,
    ) Cancelation {
        const task = self.new();
        task.@"defer"(function, context);
        return self.complete(task);
    }

    pub fn await(
        self: *Scheduler,
        function: anytype,
        context: anytype,
    ) !Waker {
        const task = self.new();
        const port = try task.await(function, context);
        const cancelation = self.submit(task);

        return .{ .port = port, .cancelation = cancelation };
    }
};

pub const Task = struct {
    const max_context_size = 128;
    const max_context_alignment = 16;

    id: ?TaskId,
    scheduler: *Scheduler,
    completion: Completion,
    cancelation: Completion,
    context: [max_context_size]u8 align(max_context_alignment),

    pub fn destroy(self: *Task) void {
        assert(self.id != null);
        self.scheduler.destroy(self.id.?);
    }

    pub fn @"defer"(
        self: *Task,
        function: anytype,
        context: anytype,
    ) void {
        const Context = @TypeOf(context);

        if (@sizeOf(Context) > Task.max_context_size or @alignOf(Context) > Task.max_context_alignment) {
            @compileError("Incorrect size/aligment for task context");
        }

        const TypeErased = struct {
            fn complete(task: *Task, _: *Completion, res: Loop.Result) bool {
                res.@"defer" catch {
                    task.destroy();
                    return false;
                };

                const _context: *Context = @ptrCast(@alignCast(&task.context));
                const rearm = @call(.auto, function, _context.*);

                if (!rearm) task.destroy();

                return rearm;
            }
        };

        @as(*Context, @ptrCast(@alignCast(&self.context))).* = context;
        self.completion.@"defer"(TypeErased.complete, self);
    }

    pub fn await(
        self: *Task,
        function: anytype,
        context: anytype,
    ) !system.mach_port_name_t {
        const Context = @TypeOf(context);

        if (@sizeOf(Context) > Task.max_context_size or @alignOf(Context) > Task.max_context_alignment) {
            @compileError("Incorrect size/aligment for task context");
        }

        const TypeErased = struct {
            fn complete(task: *Task, c: *Completion, res: Loop.Result) bool {
                res.machport catch {
                    task.destroy();
                    return false;
                };

                drain(c.operation.machport.port);
                const _context: *Context = @ptrCast(@alignCast(&task.context));
                const rearm = @call(.auto, function, _context.*);

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
                            std.log.warn("mach msg drain err, may duplicate async wakeups err={}", .{err});
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

        @as(*Context, @ptrCast(@alignCast(&self.context))).* = context;

        self.completion.mach(
            TypeErased.complete,
            self,
            .{ .port = mach_port, .buffer = .{ .array = undefined } },
        );

        return mach_port;
    }
};

pub const Cancelation = struct {
    scheduler: *Scheduler,
    id: TaskId,

    pub fn cancel(self: *const Cancelation) void {
        self.scheduler.cancel(self.id);
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

fn testDeferTask(calls: *u32) bool {
    calls.* += 1;
    return false;
}

fn testMachTask(calls: *u32) bool {
    calls.* += 1;

    return false;
}
test "task completes" {
    const gpa = testing.allocator;
    const io = testing.io;

    var alloc = heap.ArenaAllocator.init(gpa);
    defer alloc.deinit();

    const arena = alloc.allocator();

    var scheduler: Scheduler = undefined;
    try scheduler.init(arena, io);
    defer scheduler.deinit();

    var calls: u32 = 0;

    var handler = scheduler.@"defer"(testDeferTask, .{&calls});

    scheduler.run(.until_done);

    try testing.expectEqual(@as(u32, 1), calls);

    handler.cancel();

    scheduler.run(.until_done);

    try testing.expectEqual(@as(u32, 1), calls);
}

test "Async notifier completes task" {
    const gpa = testing.allocator;
    const io = testing.io;

    var alloc = heap.ArenaAllocator.init(gpa);
    defer alloc.deinit();

    const arena = alloc.allocator();

    var scheduler: Scheduler = undefined;
    try scheduler.init(arena, io);
    defer scheduler.deinit();

    var calls: u32 = 0;

    const waker = try scheduler.await(testMachTask, .{&calls});

    scheduler.run(.no_wait);
    try testing.expectEqual(@as(u32, 0), calls);

    try waker.wake();
    try waker.wake();
    try waker.wake();
    try waker.wake();
    try waker.wake();
    try waker.wake();
    try waker.wake();
    scheduler.run(.until_done);

    try testing.expectEqual(@as(u32, 1), calls);

    waker.close();
    scheduler.run(.until_done);

    try testing.expectEqual(@as(u32, 1), calls);
}

test "cancels pending task" {
    const gpa = testing.allocator;
    const io = testing.io;

    var alloc = heap.ArenaAllocator.init(gpa);
    defer alloc.deinit();

    const arena = alloc.allocator();

    var scheduler: Scheduler = undefined;
    try scheduler.init(arena, io);
    defer scheduler.deinit();

    var calls: u32 = 0;

    var cl = scheduler.@"defer"(testDeferTask, .{&calls});

    cl.cancel();

    scheduler.run(.until_done);

    try testing.expectEqual(@as(u32, 0), calls);
}

test "task can detach" {
    const gpa = testing.allocator;
    const io = testing.io;

    var alloc = heap.ArenaAllocator.init(gpa);
    defer alloc.deinit();

    const arena = alloc.allocator();

    var scheduler: Scheduler = undefined;
    try scheduler.init(arena, io);
    defer scheduler.deinit();

    var calls: u32 = 0;

    _ = scheduler.@"defer"(testDeferTask, .{&calls});

    scheduler.run(.until_done);

    try testing.expectEqual(@as(u32, 1), calls);
}
