const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const posix = std.posix;
const system = posix.system;
const testing = std.testing;
const heap = std.heap;

const datastruct = @import("datastruct.zig");
const slotmap = datastruct.slotmap;
const multi_mpsc = datastruct.multi_mpsc;
pub const TaskId = slotmap.Key;
const Loop = @import("loop.zig");
const Completion = Loop.Completion;

pub const TaskPool = struct {
    io: Io,
    mutex: Io.Mutex,
    tasks: heap.MemoryPool(Task),
    cancelations: heap.MemoryPool(Completion),
    active: slotmap.SlotMap(*Task),
    gpa: Allocator,

    pub fn init(self: *TaskPool, arena: Allocator, gpa: Allocator, io: Io) !void {
        self.* = .{
            .mutex = .init,
            .tasks = undefined,
            .active = undefined,
            .cancelations = undefined,
            .gpa = gpa,
            .io = io,
        };
        self.tasks = try .initCapacity(arena, 100);
        self.cancelations = try .initCapacity(arena, 100);
        self.active = try .init(arena, 100);
    }

    pub fn create(self: *TaskPool) *Task {
        self.lock();
        defer self.unlock();

        const task = self.tasks.create(undefined) catch @panic("Task Overflow");
        const id = self.active.put(task) catch @panic("Task Overflow");
        task.* = .{ .pool = self, .id = id, .arena = .init(self.gpa) };

        return task;
    }

    pub fn cancelation(self: *TaskPool, id: TaskId) *Completion {
        self.lock();
        defer self.unlock();

        const task = (self.active.get(id) orelse return).*;
        const completion = self.cancelations.create(undefined) catch @panic("Cancel Overflow");
        completion.cancel(
            &task.completion,
            struct {
                fn cancel(t: *Task, c: *Completion) void {
                    t.pool.lock();
                    defer t.pool.unlock();

                    t.pool.cancelations.destroy(c);
                }
            }.cancel,
            task,
        );
        return completion;
    }

    fn destroy(self: *TaskPool, id: TaskId) void {
        self.lock();
        defer self.unlock();

        const task = self.active.remove(id) orelse @panic("Destroy non-active Task");
        self.tasks.destroy(task);
    }

    pub fn lock(self: *TaskPool) void {
        self.mutex.lockUncancelable(self.io);
    }
    pub fn unlock(self: *TaskPool) void {
        self.mutex.unlock(self.io);
    }
};

pub const Task = struct {
    const MAX_SIZE = 128;
    const MAX_ALIGNMENT = 16;

    id: TaskId,
    pool: *TaskPool,
    completion: Completion = .noop,
    context: [MAX_SIZE]u8 align(MAX_ALIGNMENT) = undefined,
    arena: heap.ArenaAllocator,

    pub fn destroy(self: *Task) void {
        self.arena.deinit();
        self.pool.destroy(self.id);
    }

    pub fn assertContext(context: anytype) void {
        const Context = @TypeOf(context);

        if (@sizeOf(Context) > Task.MAX_SIZE or @alignOf(Context) > Task.MAX_ALIGNMENT) {
            @compileError("Incorrect size/alignment for task context");
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
                const _context: *Context = @ptrCast(@alignCast(&task.context));

                const rearm = @call(
                    .auto,
                    function,
                    _context.* ++
                        .{ task.arena.allocator(), res.@"defer" },
                );

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
        assertContext(context);
        const Context = @TypeOf(context);

        const TypeErased = struct {
            fn complete(task: *Task, c: *Completion, res: Loop.Result) bool {
                drain(c.operation.machport.port);
                const _context: *Context = @ptrCast(@alignCast(&task.context));
                const rearm = @call(.auto, function, _context.* ++ .{ task.arena.allocator(), res.machport });

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

    pub fn complete(self: *Task, loop: *Loop) void {
        loop.complete(&self.completion);
    }

    pub fn submit(self: *Task, loop: *Loop) void {
        loop.submit(&self.completion);
    }
};

test "Task defer allocates and copies context" {
    const gpa = testing.allocator;
    var arena: heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();

    var pool: TaskPool = undefined;
    try pool.init(arena.allocator(), gpa, testing.io);

    const Context = struct {
        value: u64,
        other: u32,
    };

    var original = Context{ .value = 0x1234_5678_9abc_def0, .other = 0xfeed_beef };
    const task = pool.create();
    defer task.destroy();
    task.@"defer"(struct {
        fn callback(_: Context, ar: Allocator, res: anyerror!void) bool {
            res catch return false;
            _ = ar.alloc(u8, 1) catch return false;
            return true;
        }
    }.callback, .{original});

    original = .{ .value = 0, .other = 0 };

    const copied: *const struct { Context } = @ptrCast(@alignCast(&task.context));
    try testing.expectEqual(@as(u64, 0x1234_5678_9abc_def0), copied.@"0".value);
    try testing.expectEqual(@as(u32, 0xfeed_beef), copied.@"0".other);
}

test "Task await allocates and copies context" {
    const gpa = testing.allocator;
    var arena: heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();

    var pool: TaskPool = undefined;
    try pool.init(arena.allocator(), gpa, testing.io);

    const Context = struct {
        value: u64,
        other: u32,
    };

    var original = Context{ .value = 0x1234_5678_9abc_def0, .other = 0xfeed_beef };
    const task = pool.create();
    defer task.destroy();
    const port = try task.await(struct {
        fn callback(_: Context, ar: Allocator, res: anyerror!void) bool {
            res catch return false;
            _ = ar.alloc(u8, 1) catch return false;
            return true;
        }
    }.callback, .{original});
    _ = system.mach_port_deallocate(
        posix.system.mach_task_self(),
        port,
    );

    original = .{ .value = 0, .other = 0 };

    const copied: *const struct { Context } = @ptrCast(@alignCast(&task.context));
    try testing.expectEqual(@as(u64, 0x1234_5678_9abc_def0), copied.@"0".value);
    try testing.expectEqual(@as(u32, 0xfeed_beef), copied.@"0".other);
}
