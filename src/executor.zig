const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const atomic = std.atomic;
const builtin = std.builtin;
const posix = std.posix;
const system = posix.system;

const datastruct = @import("datastruct.zig");
const multi_mpsc = datastruct.multi_mpsc;
const sch = @import("scheduler.zig");
const Task = sch.Task;
const Scheduler = sch.Scheduler;

const CancelationRequest = struct {
    id: sch.TaskId,
    next: ?*CancelationRequest = null,
};

const Queues = union(enum) {
    cancelations: CancelationRequest,
    completions: Task,
    submissions: Task,
};

pub const Executor = struct {
    tasks: multi_mpsc.MultiIntrusive(Queues),
    cancelations: std.heap.MemoryPool(CancelationRequest),
    scheduler: Scheduler,
    scheduler_thread: Io.Future(void),
    stop: atomic.Value(bool),

    mutex: Io.Mutex,
    io: Io,
    arena: Allocator,
    gpa: Allocator,

    pub fn init(self: *@This(), arena: Allocator, gpa: Allocator, io: Io) !void {
        self.* = .{
            .tasks = undefined,
            .cancelations = undefined,
            .scheduler = undefined,
            .scheduler_thread = undefined,
            .mutex = .init,
            .io = io,
            .gpa = gpa,
            .arena = arena,
            .stop = .init(false),
        };

        self.tasks.init();
        self.cancelations = .empty;
        try self.scheduler.init(arena, io);

        self.scheduler_thread = try io.concurrent(Executor.run, .{self});
    }

    pub fn deinit(self: *@This()) void {
        // if (builtin.mode == .Debug) self.io.sleep(.fromMilliseconds(50), .real) catch {};
        self.stop.store(true, .release);

        _ = self.scheduler_thread.await(self.io);

        self.scheduler.deinit();
    }

    pub fn @"defer"(
        self: *@This(),
        function: anytype,
        context: anytype,
    ) !Cancelation {
        self.scheduler.lock();
        defer self.scheduler.unlock();

        const task = self.scheduler.create();
        task.@"defer"(function, context);

        return .{ .executor = self, .id = task.id };
    }

    pub fn await(
        self: *@This(),
        function: anytype,
        context: anytype,
    ) !Waker {
        self.scheduler.lock();
        defer self.scheduler.unlock();

        const task = self.create();
        const port = try task.await(function, context);

        return .{ .port = port, .cancelation = .{ .id = task.id, .executor = self } };
    }

    fn run(self: *@This()) void {
        while (!self.stop.load(.acquire)) {
            while (self.tasks.pop(.cancelations)) |cancelation| {
                self.scheduler.cancel(cancelation.id);
                self.cancelations.destroy(cancelation);
            }
            while (self.tasks.pop(.completions)) |task| {
                self.scheduler.complete(task);
            }
            while (self.tasks.pop(.submissions)) |task| {
                self.scheduler.submit(task);
            }

            self.scheduler.run(.no_wait);

            self.io.sleep(.fromNanoseconds(100), .real) catch {};
        }
    }
};

pub const Cancelation = struct {
    id: sch.TaskId,
    executor: *Executor,

    pub fn cancel(self: *const Cancelation) void {
        const request = self.executor.cancelations.create(self.executor.arena) catch @panic("Cancelation Overflow");
        request.* = .{ .id = self.id };
        self.executor.tasks.push(.cancelations, request);
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
