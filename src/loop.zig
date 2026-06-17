//This event loop use as refence libxev and tigerbeetle implementations
//Sources:
// - TigerBeetle: https://github.com/tigerbeetle/tigerbeetle/tree/main [LIBXEV]
// - Libxev: https://github.com/mitchellh/libxev [TIGERBEETLE]
const std = @import("std");
const assert = std.debug.assert;
const posix = std.posix;
const Kqueue = std.Io.Kqueue;
const testing = std.testing;
const Io = std.Io;
const meta = std.meta;
const panic = std.debug.panic;
const builtin = @import("builtin");

const datastruct = @import("datastruct.zig");
const queue = datastruct.queue;
const mpsc = datastruct.mpsc;

pub const Loop = @This();

kq: posix.fd_t,

cancellations: mpsc.Intrusive(Completion),
completions: mpsc.Intrusive(Completion),
submissions: mpsc.Intrusive(Completion),
inflight: usize,

group: Io.Group,

pub fn init(self: *Loop) !void {
    const kq = posix.system.kqueue();
    self.* = .{
        .kq = kq,
        .completions = undefined,
        .cancellations = undefined,
        .submissions = undefined,
        .inflight = 0,
        .group = .init,
    };
    self.completions.init();
    self.submissions.init();
    self.cancellations.init();
}

pub fn deinit(self: *Loop, io: Io) void {
    assert(self.kq > -1);

    self.group.cancel(io);

    _ = posix.system.close(self.kq);
    self.kq = -1;
}

pub const RunMode = enum {
    no_wait,
    until_done,
};

pub fn run(self: *Loop, mode: RunMode) !void {
    switch (mode) {
        .no_wait => try self.flush(false),
        .until_done => while (!self.done()) try self.flush(false),
    }
}

pub fn done(self: *Loop) bool {
    return self.submissions.empty() and
        self.completions.empty() and
        self.inflight == 0 and
        self.group.token.load(.acquire) == null;
}

pub fn flush(self: *Loop, _: bool) !void {
    while (self.cancellations.pop()) |c| {
        c.callback(self, c);
    }

    var events: [256]posix.Kevent = undefined;

    const submitted = self.flush_submissions(&events);

    if (submitted > 0 or self.completions.empty()) {
        var timeout = std.mem.zeroes(posix.timespec);

        const completed = try Kqueue.kevent(
            self.kq,
            events[0..submitted],
            events[0..events.len],
            &timeout,
        );

        self.inflight += submitted;
        self.inflight -= completed;

        for (events[0..completed]) |ev| {
            if (ev.udata == 0) continue;

            if (ev.flags & std.c.EV.DELETE != 0) continue;

            const c: *Completion = @ptrFromInt(@as(usize, @intCast(ev.udata)));

            c.state = .completed;

            self.completions.push(c);
        }
    }

    while (self.completions.pop()) |completion| {
        completion.callback(self, completion);
        completion.state = .idle;
    }
}

pub fn flush_submissions(self: *Loop, kevents: []posix.Kevent) usize {
    var submitted: usize = 0;
    while (submitted < kevents.len) {
        const completion = self.submissions.pop() orelse return submitted;
        if (completion.state == .completed) {
            self.completions.push(completion);
            continue;
        }

        var event: posix.Kevent = undefined;
        completion.kevent(&event);

        if (completion.state == .canceled) {
            event.flags = std.c.EV.DELETE;
            completion.canceled();
            self.completions.push(completion);
        } else {
            completion.state = .active;
        }

        kevents[submitted] = event;
        submitted += 1;
    }
    return submitted;
}

pub fn submit(
    self: *Loop,
    completion: *Completion,
    callback: anytype,
    context: anytype,
    comptime op_tag: meta.Tag(Operation),
    op_data: @FieldType(Operation, @tagName(op_tag)),
    resolver: anytype,
) void {
    const Context = @TypeOf(context);

    const TypeErased = struct {
        fn complete(_: *Loop, _completion: *Completion) void {
            const result = @call(.auto, resolver, .{&@field(_completion.operation, @tagName(op_tag))});

            _completion.result = result;

            const _context: Context = @ptrCast(@alignCast(_completion.context));
            @call(.auto, callback, .{ _context, _completion, result });
        }
    };

    completion.* = .{
        .state = .submitted,
        .operation = @unionInit(Operation, @tagName(op_tag), op_data),
        .context = context,
        .callback = TypeErased.complete,
    };
    self.submissions.push(completion);
}

pub fn concurrent(
    self: *Loop,
    io: Io,
    completion: *Completion,
    callback: anytype,
    context: anytype,
    comptime op_tag: meta.Tag(Operation),
    op_data: @FieldType(Operation, @tagName(op_tag)),
    resolver: anytype,
) !void {
    completion.* = .{
        .state = .active,
        .operation = @unionInit(Operation, @tagName(op_tag), op_data),
        .context = context,
        .callback = undefined,
        .prev = null,
        .next = null,
    };

    const Context = @TypeOf(context);

    const TypeErased = struct {
        fn concurrent(_loop: *Loop, _completion: *Completion) void {
            const result = @call(.auto, resolver, .{&@field(_completion.operation, @tagName(op_tag))});

            _completion.callback = complete;
            _completion.result = result;
            _completion.state = .completed;

            _loop.completions.push(_completion);
        }

        fn complete(_: *Loop, _completion: *Completion) void {
            const _context: Context = @ptrCast(@alignCast(_completion.context));

            @call(.auto, callback, .{ _context, _completion, _completion.result.? });
        }
    };

    try self.group.concurrent(io, TypeErased.concurrent, .{ self, completion });
}

pub fn @"defer"(
    self: *Loop,
    completion: *Completion,
    callback: anytype,
    context: anytype,
) void {
    const Context = @TypeOf(context);

    const TypeErased = struct {
        fn complete(_: *Loop, _completion: *Completion) void {
            const _context: Context = @ptrCast(@alignCast(_completion.context));
            @call(.auto, callback, .{ _context, _completion, OperationResult{ .@"defer" = {} } });
        }
    };

    completion.* = .{
        .operation = .@"defer",
        .context = context,
        .callback = TypeErased.complete,
        .state = .completed,
    };

    self.completions.push(completion);
}

pub fn cancellation(
    self: *Loop,
    completion: *Completion,
    target: *Completion,
    callback: anytype,
    context: anytype,
) void {
    const Context = @TypeOf(context);

    const TypeErased = struct {
        fn complete(loop: *Loop, _completion: *Completion) void {
            const _target = _completion.operation.cancel;

            switch (_target.state) {
                .idle, .canceled => {},
                .completed, .submitted => _target.canceled(),
                .active => {
                    _target.state = .canceled;
                    loop.submissions.push(_target);
                },
            }

            const _context: Context = @ptrCast(@alignCast(_completion.context));
            @call(.auto, callback, .{ _context, _completion, OperationResult{ .cancel = {} } });
        }
    };

    completion.operation = .{ .cancel = target };
    completion.context = context;
    completion.callback = TypeErased.complete;

    self.cancellation.push(completion);
}

pub const Operation = union(OperationType) {
    noop: void,
    @"defer": void,
    read: Read,
    machport: MachPort,
    cancel: *Completion,

    pub const Read = struct {
        fd: posix.fd_t,
        buffer: []u8,
    };

    pub const MachPort = struct {
        port: posix.system.mach_port_name_t,
        buffer: []u8,
    };
};

const OperationType = enum {
    noop,
    @"defer",
    read,
    machport,
    cancel,
};

const Canceled = error{Canceled};
const ReadError = Canceled || posix.ReadError;

pub const OperationResult = union(OperationType) {
    noop: void,
    @"defer": Canceled!void,
    read: ReadError!usize,
    machport: Canceled!void,
    cancel: void,
};

const State = enum {
    idle,
    submitted,
    canceled,
    active,
    completed,
};

pub const Completion = struct {
    pub const noop: Completion = .{
        .operation = .noop,
        .context = null,
        .callback = noopCallback,
        .state = .idle,
    };

    operation: Operation,
    result: ?OperationResult = null,

    context: ?*anyopaque,
    callback: *const fn (loop: *Loop, completion: *Completion) void,

    prev: ?*Completion = null,
    next: ?*Completion = null,

    state: State,

    pub fn noopCallback(_: *Loop, _: *Completion) void {}

    pub fn canceled(self: *Completion) void {
        self.state = .completed;
        switch (self.operation) {
            .noop, .cancel => {},
            .read => self.result = .{ .read = error.Canceled },
            .@"defer" => self.result = .{ .@"defer" = error.Canceled },
            .machport => self.result = .{ .machport = error.Canceled },
        }
    }

    pub fn kevent(self: *Completion, event: *posix.Kevent) void {
        switch (self.operation) {
            .read, .cancel, .noop, .@"defer" => panic("{s} operation reached the submissions queueu", .{@tagName(self.operation)}),
            .machport => |mach| {
                event.* = .{
                    .ident = @as(c_uint, mach.port),
                    .filter = std.c.EVFILT.MACHPORT,
                    .flags = std.c.EV.ADD | std.c.EV.ENABLE | std.c.EV.ONESHOT,
                    .fflags = @bitCast(std.c.MACH.RCV{ .MSG = true }),
                    .data = 0,
                    .udata = @intFromPtr(self),
                };
            },
        }
    }
};

test "defer" {
    const io = testing.io;

    var loop: Loop = undefined;
    try loop.init();
    defer loop.deinit(io);

    var context: u64 = 0;
    var completion: Completion = .noop;

    loop.@"defer"(&completion, struct {
        pub fn @"defer"(_context: *u64, _: *Completion, _: OperationResult) void {
            _context.* += 1;
        }
    }.@"defer", &context);

    try testing.expectEqual(context, 0);

    try loop.run(.no_wait);

    try testing.expectEqual(context, 1);
}

test "read" {
    const io = testing.io;

    var loop: Loop = undefined;
    try loop.init();
    defer loop.deinit(io);

    const contents = "hello from loop";
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const file = try tmp.dir.createFile(io, "read.txt", .{ .read = true });
    defer file.close(io);
    try file.writeStreamingAll(io, contents);
    try testing.expectEqual(@as(i64, 0), posix.system.lseek(file.handle, 0, posix.SEEK.SET));

    var buffer: [contents.len]u8 = undefined;
    var completion: Completion = .noop;
    var called = false;

    const Resolver = struct {
        pub fn perform(self: *Operation.Read) OperationResult {
            return .{ .read = posix.read(self.fd, self.buffer) };
        }
    };

    loop.concurrent(testing.io, &completion, struct {
        fn read(_called: *bool, _: *Completion, result: OperationResult) void {
            _called.* = true;
            testing.expectEqual(@as(usize, contents.len), result.read catch unreachable) catch unreachable;
        }
    }.read, &called, .read, .{
        .fd = file.handle,
        .buffer = &buffer,
    }, Resolver.perform) catch unreachable;

    try testing.expect(!called);

    try loop.run(.until_done);

    try testing.expect(called);
    try testing.expectEqualStrings(contents, &buffer);
}

test "mach port" {
    const io = testing.io;
    const c = std.c;

    var loop: Loop = undefined;
    try loop.init();
    defer loop.deinit(io);

    const mach_self = c.mach_task_self();
    var mach_port: c.mach_port_name_t = undefined;
    try testing.expectEqual(@as(c.kern_return_t, 0), c.mach_port_allocate(
        mach_self,
        c.MACH.PORT.RIGHT.RECEIVE,
        &mach_port,
    ));
    defer _ = c.mach_port_deallocate(mach_self, mach_port);

    var buffer: [@sizeOf(c.mach_msg_header_t)]u8 = undefined;
    var completion: Completion = .noop;
    var called = false;

    loop.submit(&completion, struct {
        fn machport(_called: *bool, _: *Completion, _: OperationResult) void {
            _called.* = true;
        }
    }.machport, &called, .machport, .{
        .port = mach_port,
        .buffer = &buffer,
    }, struct {
        fn machport(_: *Operation.MachPort) OperationResult {
            return .{ .machport = {} };
        }
    }.machport);

    for (0..10) |_| try loop.run(.no_wait);
    try testing.expect(!called);

    var msg: c.mach_msg_header_t = .{
        .msgh_bits = @intFromEnum(c.MACH.MSG.TYPE.MAKE_SEND_ONCE),
        .msgh_size = @sizeOf(c.mach_msg_header_t),
        .msgh_remote_port = mach_port,
        .msgh_local_port = c.MACH.PORT.NULL,
        .msgh_voucher_port = undefined,
        .msgh_id = undefined,
    };
    try testing.expectEqual(c.mach_msg_return_t.SUCCESS, c.mach_msg(
        &msg,
        .{ .SEND = .{} },
        msg.msgh_size,
        0,
        c.MACH.PORT.NULL,
        c.MACH.MSG.TIMEOUT_NONE,
        c.MACH.PORT.NULL,
    ));

    try loop.run(.until_done);
    try testing.expect(called);

    called = false;

    try loop.run(.no_wait);
    try testing.expect(!called);
}
