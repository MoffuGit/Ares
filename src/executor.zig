const std = @import("std");
const heap = std.heap;
const Allocator = std.mem.Allocator;
const Io = std.Io;
const testing = std.testing;
const debug = std.debug;
const atomic = std.atomic;

const Loop = @import("loop.zig");
const Completion = Loop.Completion;

pub const ForegroundExecutor = struct {
    worker: Worker,

    pub fn init(self: *ForegroundExecutor, gpa: Allocator) !void {
        try self.worker.init(gpa);
    }

    pub fn run(self: *ForegroundExecutor) void {
        self.worker.run(.no_wait);
    }

    pub fn deinit(self: *ForegroundExecutor, io: Io) void {
        self.worker.deinit(io);
    }

    pub fn @"defer"(self: *ForegroundExecutor, function: anytype, args: anytype) !Handler {
        return try self.worker.@"defer"(function, args);
    }
};

pub const BackgroundExecutor = struct {
    workers: []Worker,
    group: Io.Group,

    pub fn init(self: *BackgroundExecutor, gpa: Allocator, io: Io) !void {
        const cpu_count = try std.Thread.getCpuCount();

        const workers = try gpa.alloc(Worker, cpu_count);
        errdefer gpa.free(workers);

        self.* = .{
            .workers = workers,
            .group = .init,
        };

        for (self.workers) |*worker| {
            try worker.init(gpa);
            try self.group.concurrent(io, Worker.run, .{ worker, .until_done });
        }
    }

    pub fn deinit(self: *BackgroundExecutor, gpa: Allocator, io: Io) void {
        self.group.cancel(io);

        for (self.workers) |*worker| {
            worker.deinit(io);
        }

        gpa.free(self.workers);
    }
};

var worker_next_id: u32 = 0;

const Worker = struct {
    loop: Loop,
    gpa: Allocator,
    id: u32,

    pub fn init(self: *Worker, gpa: Allocator) !void {
        self.* = .{
            .gpa = gpa,
            .id = worker_next_id,
            .loop = undefined,
        };

        worker_next_id += 1;
        try self.loop.init();
    }

    pub fn run(self: *Worker, mode: Loop.RunMode) void {
        self.loop.run(mode) catch |err| {
            debug.panic("Worker {} loop err: {}", .{ self.id, err });
        };
    }

    pub fn @"defer"(
        self: *Worker,
        function: anytype,
        context: std.meta.ArgsTuple(@TypeOf(function)),
    ) !Handler {
        const Context = @TypeOf(context);

        const TypeErased = struct {
            fn complete(task: *Task, _: *Completion, _: Loop.Result) void {
                if (!task.isCanceled()) {
                    const _context: *Context = @ptrCast(@alignCast(task.context.ptr));
                    @call(.auto, function, _context.*);
                }

                task.complete();
            }
        };

        const task = try self.gpa.create(Task);
        errdefer self.gpa.destroy(task);

        const copy = try self.gpa.create(Context);
        errdefer self.gpa.destroy(copy);
        copy.* = context;

        task.* = .{
            .completion = .noop,
            .cancelation = .noop,
            .worker = self,
            .context = std.mem.asBytes(copy),
            .alignment = @alignOf(Context),
        };

        self.loop.@"defer"(&task.completion, TypeErased.complete, task);
        return .{ .task = task };
    }

    pub fn deinit(self: *Worker, io: Io) void {
        self.loop.deinit(io);
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

        self.worker.loop.cancel(&self.cancelation, &self.completion, cancelCallback, self);
    }

    pub fn cancelCallback(self: *Task, _: *Completion, _: Loop.Result) void {
        self.release();
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

    fn isCanceled(self: *Task) bool {
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

fn testDeferTask(calls: *u32) void {
    calls.* += 1;
}

test "task completes and stays alive until handler detaches" {
    const gpa = testing.allocator;
    const io = testing.io;

    var worker: Worker = undefined;
    try worker.init(gpa);
    defer worker.deinit(io);

    var calls: u32 = 0;

    var handler = try worker.@"defer"(testDeferTask, .{&calls});

    worker.run(.until_done);

    try testing.expectEqual(@as(u32, 1), calls);

    handler.drop();

    worker.run(.until_done);

    try testing.expectEqual(@as(u32, 1), calls);
}

test "task can be canceled before it runs" {
    const gpa = testing.allocator;
    const io = testing.io;

    var worker: Worker = undefined;
    try worker.init(gpa);
    defer worker.deinit(io);

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
    try worker.init(gpa);
    defer worker.deinit(io);

    var calls: u32 = 0;

    var handler = try worker.@"defer"(testDeferTask, .{&calls});
    handler.drop();

    worker.run(.until_done);

    try testing.expectEqual(@as(u32, 0), calls);
}

test "task can be detach" {
    const gpa = testing.allocator;
    const io = testing.io;

    var worker: Worker = undefined;
    try worker.init(gpa);
    defer worker.deinit(io);

    var calls: u32 = 0;

    var handler = try worker.@"defer"(testDeferTask, .{&calls});
    handler.detach();

    worker.run(.until_done);

    try testing.expectEqual(@as(u32, 1), calls);
}
