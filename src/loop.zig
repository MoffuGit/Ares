//This event loop use as refence libxev and tigerbeetle implementations
//Sources:
// - TigerBeetle: https://github.com/tigerbeetle/tigerbeetle/tree/main [LIBXEV]
// - Libxev: https://github.com/mitchellh/libxev [TIGERBEETLE]

const std = @import("std");
const assert = std.debug.assert;
const posix = std.posix;
const testing = std.testing;
const Io = std.Io;
const meta = std.meta;
const panic = std.debug.panic;
const Kevent = std.c.kevent64_s;
const builtin = @import("builtin");

const datastruct = @import("datastruct.zig");
const multi_mpsc = datastruct.multi_mpsc;

const Queues = union(enum) {
    cancellations: Completion,
    canceling: Completion,
    completions: Completion,
    submissions: Completion,
};

pub const Loop = @This();

kq: posix.fd_t,

queues: multi_mpsc.MultiIntrusive(Queues),
inflight: usize,
stopped: bool,

io: Io,
group: Io.Group,

pub fn init(self: *Loop, io: Io) !void {
    const kq = posix.system.kqueue();

    switch (posix.errno(kq)) {
        .SUCCESS => {},
        else => |err| return posix.unexpectedErrno(err),
    }

    self.* = .{
        .io = io,
        .kq = kq,
        .queues = undefined,
        .inflight = 0,
        .stopped = false,
        .group = .init,
    };
    self.queues.init();
}

pub fn deinit(self: *Loop) void {
    assert(self.kq > -1);

    self.group.cancel(self.io);

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
    return self.stopped or
        (self.queues.empty(.submissions) and
            self.queues.empty(.completions) and
            self.inflight == 0 and
            self.group.token.load(.acquire) == null);
}

pub fn stop(self: *Loop) void {
    self.stopped = true;
}

pub fn flush(self: *Loop, _: bool) !void {
    while (self.queues.pop(.cancellations)) |c| {
        _ = c.callback(self, c);
    }

    var events: [256]Kevent = undefined;

    const canceled = self.flush_cancellations(&events);
    const active = if (canceled < events.len)
        self.flush_submissions(events[canceled..])
    else
        0;
    const submitted = canceled + active;

    if (submitted > 0 or self.queues.empty(.completions)) {
        var timeout = std.mem.zeroes(posix.timespec);

        const completed = try kevent(
            self.kq,
            events[0..submitted],
            events[0..events.len],
            &timeout,
        );

        self.inflight += active;

        for (events[0..completed]) |ev| {
            if (ev.udata == 0) continue;

            if (ev.flags & std.c.EV.DELETE != 0) continue;

            self.inflight -= 1;

            const c: *Completion = @ptrFromInt(@as(usize, @intCast(ev.udata)));

            c.state = .completed;

            self.queues.push(.completions, c);
        }
    }

    while (self.queues.pop(.completions)) |completion| {
        completion.state = .idle;
        if (completion.callback(self, completion)) {
            completion.state = .submitted;
            self.queues.push(.submissions, completion);
        }
    }
}

pub fn flush_cancellations(self: *Loop, kevents: []Kevent) usize {
    var submitted: usize = 0;

    while (submitted < kevents.len) {
        const event = &kevents[submitted];
        const completion = self.queues.pop(.canceling) orelse break;
        submitted += 1;

        self.inflight -= 1;

        completion.kevent(event);
        event.flags = std.c.EV.DELETE;
        completion.canceled();
        self.queues.push(.completions, completion);
    }

    return submitted;
}

pub fn flush_submissions(self: *Loop, kevents: []Kevent) usize {
    var active: usize = 0;

    while (active < kevents.len) {
        const completion = self.queues.pop(.submissions) orelse break;

        if (completion.state == .completed) {
            self.queues.push(.completions, completion);
            continue;
        }

        const event = &kevents[active];
        completion.kevent(event);
        completion.state = .active;
        active += 1;
    }

    return active;
}

fn kevent(
    kq: posix.fd_t,
    changelist: []const Kevent,
    eventlist: []Kevent,
    timeout: ?*const posix.timespec,
) !usize {
    while (true) {
        const rc = std.c.kevent64(
            kq,
            changelist.ptr,
            @intCast(changelist.len),
            eventlist.ptr,
            @intCast(eventlist.len),
            .{},
            timeout,
        );

        switch (posix.errno(rc)) {
            .SUCCESS => return @intCast(rc),
            .INTR => continue,
            .ACCES => return error.AccessDenied,
            .NOENT => return error.EventNotFound,
            .NOMEM => return error.SystemResources,
            else => return error.Unexpected,
        }
    }
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
        fn complete(_: *Loop, _completion: *Completion) bool {
            if (_completion.result == null) {
                _completion.result = @call(.auto, resolver, .{@field(_completion.operation, @tagName(op_tag))});
            }

            const _context: Context = @ptrCast(@alignCast(_completion.context));
            return @call(.auto, callback, .{ _context, _completion, _completion.result.? });
        }
    };

    completion.* = .{
        .state = .submitted,
        .operation = @unionInit(Operation, @tagName(op_tag), op_data),
        .context = context,
        .callback = TypeErased.complete,
    };
    self.queues.push(.submissions, completion);
}

pub fn concurrent(
    self: *Loop,
    completion: *Completion,
    callback: anytype,
    context: anytype,
    comptime op_tag: meta.Tag(Operation),
    op_data: @FieldType(Operation, @tagName(op_tag)),
    resolver: anytype,
) !void {
    const Context = @TypeOf(context);

    const TypeErased = struct {
        fn _concurrent(_loop: *Loop, _completion: *Completion) void {
            const result = @call(.auto, resolver, .{@field(_completion.operation, @tagName(op_tag))});

            _completion.result = result;
            _completion.state = .completed;

            _loop.queues.push(.completions, _completion);
        }

        fn complete(loop: *Loop, _completion: *Completion) bool {
            const _context: Context = @ptrCast(@alignCast(_completion.context));

            if (@call(.auto, callback, .{ _context, _completion, _completion.result.? })) {
                _completion.state = .concurrent;
                loop.group.concurrent(loop.io, _concurrent, .{ loop, _completion }) catch |err| {
                    std.log.err("Can't add concurrent call: {}", .{err});
                };
            }

            return false;
        }
    };

    completion.* = .{
        .state = .concurrent,
        .operation = @unionInit(Operation, @tagName(op_tag), op_data),
        .context = context,
        .callback = TypeErased.complete,
        .next = null,
    };

    try self.group.concurrent(self.io, TypeErased._concurrent, .{ self, completion });
}

pub fn @"defer"(
    self: *Loop,
    completion: *Completion,
    callback: anytype,
    context: anytype,
) void {
    const Context = @TypeOf(context);

    const TypeErased = struct {
        fn complete(_: *Loop, _completion: *Completion) bool {
            const _context: Context = @ptrCast(@alignCast(_completion.context));
            return @call(.auto, callback, .{ _context, _completion, Result{ .@"defer" = {} } });
        }
    };

    completion.* = .{
        .operation = .@"defer",
        .context = context,
        .callback = TypeErased.complete,
        .state = .completed,
    };

    self.queues.push(.completions, completion);
}

pub fn cancel(
    self: *Loop,
    completion: *Completion,
    target: *Completion,
    callback: anytype,
    context: anytype,
) void {
    const Context = @TypeOf(context);

    const TypeErased = struct {
        fn complete(loop: *Loop, _completion: *Completion) bool {
            const _target = _completion.operation.cancel;

            switch (_target.state) {
                .idle, .canceled, .concurrent => {},
                .completed, .submitted => _target.canceled(),
                .active => {
                    _target.state = .canceled;
                    loop.queues.push(.canceling, _target);
                },
            }

            const _context: Context = @ptrCast(@alignCast(_completion.context));
            @call(.auto, callback, .{ _context, _completion, Result{ .cancel = {} } });

            return false;
        }
    };

    completion.* = .{
        .operation = .{ .cancel = target },
        .context = context,
        .callback = TypeErased.complete,
        .state = .submitted,
    };

    self.queues.push(.cancellations, completion);
}

pub fn read(
    self: *Loop,
    completion: *Completion,
    function: anytype,
    context: anytype,
    data: Read,
) !void {
    try self.concurrent(
        completion,
        function,
        context,
        .read,
        data,
        struct {
            fn read(op: Read) Result {
                const buffer: []u8 = switch (op.buffer) {
                    .slice => |slice| slice,
                    .array => |array| @constCast(&array),
                };
                return .{ .read = posix.read(op.fd, buffer) };
            }
        }.read,
    );
}

pub fn mach(
    self: *Loop,
    completion: *Completion,
    function: anytype,
    context: anytype,
    data: MachPort,
) void {
    self.submit(
        completion,
        function,
        context,
        .machport,
        data,
        struct {
            fn machport(_: MachPort) Result {
                return .{ .machport = {} };
            }
        }.machport,
    );
}

pub const ReadBuffer = union(enum) {
    slice: []u8,
    array: [32]u8,
};

pub const Read = struct {
    fd: posix.fd_t,
    buffer: ReadBuffer,
};

pub const MachPort = struct {
    port: posix.system.mach_port_name_t,
    buffer: ReadBuffer,
};

pub const Operation = union(OperationType) {
    noop: void,
    @"defer": void,
    read: Read,
    machport: MachPort,
    cancel: *Completion,
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

pub const Result = union(OperationType) {
    noop: void,
    @"defer": Canceled!void,
    read: ReadError!usize,
    machport: Canceled!void,
    cancel: void,
};

const State = enum {
    concurrent,
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
    result: ?Result = null,

    context: ?*anyopaque,
    callback: *const fn (loop: *Loop, completion: *Completion) bool,

    next: ?*Completion = null,

    state: State,

    pub fn noopCallback(_: *Loop, _: *Completion) bool {
        return false;
    }

    pub fn canceled(self: *Completion) void {
        self.state = .completed;
        switch (self.operation) {
            .noop, .cancel => {},
            .read => self.result = .{ .read = error.Canceled },
            .@"defer" => self.result = .{ .@"defer" = error.Canceled },
            .machport => self.result = .{ .machport = error.Canceled },
        }
    }

    pub fn kevent(self: *Completion, event: *Kevent) void {
        switch (self.operation) {
            .read, .cancel, .noop, .@"defer" => panic("{s} operation reached the submissions queueu", .{@tagName(self.operation)}),
            .machport => |m| {
                const buffer: []u8 = switch (m.buffer) {
                    .slice => |slice| slice,
                    .array => |array| @constCast(&array),
                };
                event.* = .{
                    .ident = @intCast(m.port),
                    .filter = std.c.EVFILT.MACHPORT,
                    .flags = std.c.EV.ADD | std.c.EV.ENABLE,
                    .fflags = @bitCast(std.c.MACH.RCV{ .MSG = true }),
                    .data = 0,
                    .udata = @intFromPtr(self),
                    .ext = .{
                        @intFromPtr(buffer.ptr),
                        buffer.len,
                    },
                };
            },
        }
    }
};

test "defer" {
    const io = testing.io;

    var loop: Loop = undefined;
    try loop.init(io);
    defer loop.deinit();

    var context: u64 = 0;
    var completion: Completion = .noop;

    loop.@"defer"(&completion, struct {
        pub fn @"defer"(_context: *u64, _: *Completion, _: Result) bool {
            _context.* += 1;
            return false;
        }
    }.@"defer", &context);

    try testing.expectEqual(context, 0);

    try loop.run(.no_wait);

    try testing.expectEqual(context, 1);
}

test "read" {
    const io = testing.io;

    var loop: Loop = undefined;
    try loop.init(io);
    defer loop.deinit();

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

    try loop.read(
        &completion,
        struct {
            fn read(_called: *bool, _: *Completion, _: Result) bool {
                _called.* = true;
                return false;
            }
        }.read,
        &called,
        .{
            .fd = file.handle,
            .buffer = .{ .slice = &buffer },
        },
    );

    try testing.expect(!called);

    try loop.run(.until_done);

    try testing.expect(called);
    try testing.expectEqualStrings(contents, &buffer);
}

test "read rearm" {
    const io = testing.io;

    var loop: Loop = undefined;
    try loop.init(io);
    defer loop.deinit();

    const contents = "hello again";
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const file = try tmp.dir.createFile(io, "read-rearm.txt", .{ .read = true });
    defer file.close(io);
    try file.writeStreamingAll(io, contents ++ contents);
    try testing.expectEqual(@as(i64, 0), posix.system.lseek(file.handle, 0, posix.SEEK.SET));

    var buffer: [contents.len]u8 = undefined;
    var completion: Completion = .noop;
    var calls: usize = 0;

    try loop.read(
        &completion,
        struct {
            fn read(_calls: *usize, _: *Completion, res: Result) bool {
                const read_len = res.read catch @panic("read failed");

                _calls.* += 1;
                return read_len > 0;
            }
        }.read,
        &calls,
        .{
            .fd = file.handle,
            .buffer = .{ .slice = &buffer },
        },
    );

    try loop.run(.until_done);

    try testing.expectEqual(@as(usize, 3), calls);
    try testing.expectEqualStrings(contents, &buffer);
}

test "mach port" {
    const io = testing.io;

    var loop: Loop = undefined;
    try loop.init(io);
    defer loop.deinit();

    const mach_self = posix.system.mach_task_self();
    var mach_port: posix.system.mach_port_name_t = undefined;
    try testing.expectEqual(posix.system.mach_msg_return_t.SUCCESS, @as(
        posix.system.mach_msg_return_t,
        @enumFromInt(
            posix.system.mach_port_allocate(
                mach_self,
                posix.system.MACH.PORT.RIGHT.RECEIVE,
                &mach_port,
            ),
        ),
    ));
    defer _ = posix.system.mach_port_deallocate(mach_self, mach_port);

    var called = false;
    var buffer: [@sizeOf(posix.system.mach_msg_header_t)]u8 = undefined;
    var completion: Completion = .noop;

    loop.mach(
        &completion,
        struct {
            fn machport(_called: *bool, _: *Completion, res: Result) bool {
                if (res.machport != error.Canceled) {
                    _called.* = true;
                }
                return false;
            }
        }.machport,
        &called,
        .{
            .port = mach_port,
            .buffer = .{ .slice = &buffer },
        },
    );

    // Tick so we submit... should not call since we never sent.
    try loop.run(.no_wait);
    try testing.expect(!called);

    // Send a message to the port
    var msg: posix.system.mach_msg_header_t = .{
        .msgh_bits = @intFromEnum(posix.system.MACH.MSG.TYPE.MAKE_SEND_ONCE),
        .msgh_size = @sizeOf(posix.system.mach_msg_header_t),
        .msgh_remote_port = mach_port,
        .msgh_local_port = posix.system.MACH.PORT.NULL,
        .msgh_voucher_port = undefined,
        .msgh_id = undefined,
    };

    try testing.expectEqual(
        posix.system.mach_msg_return_t.SUCCESS,
        posix.system.mach_msg(
            &msg,
            .{ .SEND = .{} },
            msg.msgh_size,
            0,
            posix.system.MACH.PORT.NULL,
            posix.system.MACH.MSG.TIMEOUT_NONE,
            posix.system.MACH.PORT.NULL,
        ),
    );
    // We should receive now!
    try loop.run(.until_done);
    try testing.expect(called);

    // We should not receive again
    called = false;
    loop.mach(
        &completion,
        struct {
            fn machport(_called: *bool, _: *Completion, res: Result) bool {
                if (res.machport != error.Canceled) {
                    _called.* = true;
                }
                return false;
            }
        }.machport,
        &called,
        .{
            .port = mach_port,
            .buffer = .{ .slice = &buffer },
        },
    );

    // Tick so we submit... should not call since we never sent.
    try loop.run(.no_wait);
    try loop.run(.no_wait);
    try testing.expect(!called);
}

test "cancel mach port" {
    const io = testing.io;
    const c = std.c;

    var loop: Loop = undefined;
    try loop.init(io);
    defer loop.deinit();

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

    loop.mach(
        &completion,
        struct {
            fn machport(_called: *bool, _: *Completion, res: Result) bool {
                if (res.machport != error.Canceled) {
                    _called.* = true;
                }
                return false;
            }
        }.machport,
        &called,
        .{
            .port = mach_port,
            .buffer = .{ .slice = &buffer },
        },
    );

    for (0..10) |_| try loop.run(.no_wait);
    try testing.expect(!called);

    const Cancelled = struct {
        fn cancel(context: *bool, _: *Completion, _: Result) void {
            context.* = true;
        }
    };
    var canceled: bool = false;
    var cancellation: Completion = .noop;

    loop.cancel(&cancellation, &completion, Cancelled.cancel, &canceled);

    for (0..10) |_| try loop.run(.no_wait);

    try testing.expect(canceled);
    try testing.expect(!called);

    // Send a message to the port
    var msg: posix.system.mach_msg_header_t = .{
        .msgh_bits = @intFromEnum(posix.system.MACH.MSG.TYPE.MAKE_SEND_ONCE),
        .msgh_size = @sizeOf(posix.system.mach_msg_header_t),
        .msgh_remote_port = mach_port,
        .msgh_local_port = posix.system.MACH.PORT.NULL,
        .msgh_voucher_port = undefined,
        .msgh_id = undefined,
    };

    try testing.expectEqual(
        posix.system.mach_msg_return_t.SUCCESS,
        posix.system.mach_msg(
            &msg,
            .{ .SEND = .{} },
            msg.msgh_size,
            0,
            posix.system.MACH.PORT.NULL,
            posix.system.MACH.MSG.TIMEOUT_NONE,
            posix.system.MACH.PORT.NULL,
        ),
    );
    // We should receive now!
    for (0..10) |_| try loop.run(.no_wait);
    try testing.expect(!called);
}
