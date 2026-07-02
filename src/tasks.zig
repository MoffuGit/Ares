const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const posix = std.posix;
const system = posix.system;
const testing = std.testing;
const heap = std.heap;
const debug = std.debug;
const panic = debug.panic;

const chunk_pool = @import("chunk_pool.zig");
const ChunkAllocator = chunk_pool.ChunkAllocator;
const constants = @import("contants.zig");
const MAX_SIZE = constants.MAX_SIZE;
const MAX_ALIGN = constants.MAX_ALIGN;
const datastruct = @import("datastruct.zig");
const slotmap = datastruct.slotmap;
const multi_mpsc = datastruct.multi_mpsc;
pub const TaskId = slotmap.Key;
const Loop = @import("loop.zig");
const Completion = Loop.Completion;

pub const Tasks = @This();

io: Io,
mutex: Io.Mutex,
pool: heap.MemoryPool(Task),
cancelations: heap.MemoryPool(Cancelation),
active: slotmap.SlotMap(*Task),
chunks: Allocator,

pub fn init(self: *Tasks, arena: Allocator, chunks: Allocator, io: Io) !void {
    self.* = .{
        .chunks = chunks,
        .mutex = .init,
        .pool = undefined,
        .active = undefined,
        .cancelations = undefined,
        .io = io,
    };
    self.pool = try .initCapacity(arena, 100);
    self.cancelations = try .initCapacity(arena, 100);
    self.active = try .init(arena, 100);
}

pub fn create(self: *Tasks) *Task {
    self.lock();
    defer self.unlock();

    const context = self.chunks.rawAlloc(
        MAX_SIZE,
        MAX_ALIGN,
        @returnAddress(),
    ) orelse @panic("Task Context Overflow");

    const task = self.pool.create(undefined) catch @panic("Task Overflow");
    const id = self.active.put(task) catch @panic("Task Overflow");
    task.* = .{ .pool = self, .id = id, .context = context };

    return task;
}

pub fn contains(self: *Tasks, id: TaskId) bool {
    self.lock();
    defer self.unlock();

    return self.active.contains(id);
}

pub fn cancelation(self: *Tasks, id: TaskId) ?*Cancelation {
    self.lock();
    defer self.unlock();

    const task = (self.active.get(id) orelse return null).*;
    const cancel = self.cancelations.create(undefined) catch @panic("Cancel Overflow");
    cancel.* = .{
        .id = id,
        .pool = self,
    };

    cancel.completion.cancel(
        &task.completion,
        struct {
            fn _cancel(c: *Cancelation, _: *Completion) void {
                const pool = c.pool;
                pool.lock();
                defer pool.unlock();
                pool.cancelations.destroy(c);
            }
        }._cancel,
        cancel,
    );
    return cancel;
}

fn destroy(self: *Tasks, id: TaskId) void {
    self.lock();
    defer self.unlock();

    const task = self.active.remove(id) orelse @panic("Destroy non-active Task");

    self.chunks.rawFree(
        @as([*]u8, @ptrCast(task.context))[0..MAX_SIZE],
        MAX_ALIGN,
        @returnAddress(),
    );

    self.pool.destroy(task);
}

pub fn destroy_cancelation(self: *Tasks, cal: *Cancelation) void {
    self.lock();
    defer self.unlock();

    self.cancelations.destroy(cal);
}

pub fn lock(self: *Tasks) void {
    self.mutex.lockUncancelable(self.io);
}
pub fn unlock(self: *Tasks) void {
    self.mutex.unlock(self.io);
}

pub const Cancelation = struct {
    id: TaskId,
    completion: Completion = .noop,
    pool: *Tasks,
    next: ?*Cancelation = null,

    pub fn cancel(self: *Cancelation, loop: *Loop) void {
        loop.cancel(&self.completion);
    }
};

pub const Task = struct {
    id: TaskId,
    pool: *Tasks,
    completion: Completion = .noop,
    context: *anyopaque,
    next: ?*Task = null,

    pub fn destroy(self: *Task) void {
        self.pool.destroy(self.id);
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
                    _context.* ++
                        .{res.@"defer"},
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
        next_ms: u64,
        time: *Loop.Time,
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

        self.completion.timer(TypeErased.complete, self, time.next_tick(next_ms));
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
                std.log.debug("mach msg err={}", .{e});
            },
            else => |e| {
                std.log.warn("mach msg err={}", .{e});
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

    var pool: Tasks = undefined;
    try pool.init(arena.allocator(), chunks.allocator(), testing.io);

    const Context = struct {
        value: u64,
        other: u32,
    };

    var original = Context{ .value = 0x1234_5678_9abc_def0, .other = 0xfeed_beef };
    const task = pool.create();
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

    var pool: Tasks = undefined;
    try pool.init(arena.allocator(), chunks.allocator(), testing.io);

    const Context = struct {
        value: u64,
        other: u32,
    };

    var original = Context{ .value = 0x1234_5678_9abc_def0, .other = 0xfeed_beef };
    const task = pool.create();
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

    var pool: Tasks = undefined;
    try pool.init(arena.allocator(), chunks.allocator(), testing.io);

    const task = pool.create();
    defer task.destroy();

    try testing.expect(pool.cancelation(task.id) != null);
}
