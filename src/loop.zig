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

completions: mpsc.Intrusive(Completion),
submissions: mpsc.Intrusive(Completion),
inflight: usize,

group: Io.Group,

pub fn init(self: *Loop) !void {
    const kq = posix.system.kqueue();
    self.* = .{
        .kq = kq,
        .completions = undefined,
        .submissions = undefined,
        .inflight = 0,
        .group = .init,
    };
    self.completions.init();
    self.submissions.init();
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
    return self.submissions.empty() and self.completions.empty() and self.inflight == 0;
}

pub fn flush(self: *Loop, _: bool) !void {
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

            self.completions.push(c);
        }
    }

    while (self.completions.pop()) |completion| {
        completion.callback(self, completion);
    }
}

pub fn flush_submissions(self: *Loop, kevents: []posix.Kevent) usize {
    for (kevents, 0..) |*event, acc| {
        const completion = self.submissions.pop() orelse return acc;

        switch (completion.operation) {
            .read, .noop, .@"defer" => panic("{s} operation reached the submissions queueu", .{@tagName(completion.operation)}),
            .machport => |mach| {
                event.* = .{
                    .ident = @as(c_uint, mach.port),
                    .filter = std.c.EVFILT.MACHPORT,
                    .flags = std.c.EV.ADD | std.c.EV.ENABLE | std.c.EV.ONESHOT,
                    .fflags = @bitCast(std.c.MACH.RCV{ .MSG = true }),
                    .data = 0,
                    .udata = @intFromPtr(completion),
                };
            },
        }
    }

    return kevents.len;
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

            const _context: Context = @ptrCast(@alignCast(_completion.context));

            @call(.auto, callback, .{ _context, _completion, result });
        }
    };

    completion.* = .{
        .operation = @unionInit(Operation, @tagName(op_tag), op_data),
        .context = @ptrCast(@alignCast(context)),
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
        .operation = @unionInit(Operation, @tagName(op_tag), op_data),
        .context = @ptrCast(@alignCast(context)),
        .callback = undefined,
        .prev = null,
        .next = null,
    };

    const Context = @TypeOf(context);
    self.inflight += 1;

    const TypeErased = struct {
        fn concurrent(_loop: *Loop, _completion: *Completion) void {
            const data = &@field(_completion.operation, @tagName(op_tag));
            data.result = @call(.auto, resolver, .{data});

            _completion.callback = complete;

            _loop.completions.push(_completion);
        }

        fn complete(_loop: *Loop, _completion: *Completion) void {
            const data = &@field(_completion.operation, @tagName(op_tag));
            const _context: Context = @ptrCast(@alignCast(_completion.context));
            _loop.inflight -= 1;

            @call(.auto, callback, .{ _context, _completion, data.result });
        }
    };

    try self.group.concurrent(io, TypeErased.concurrent, .{ self, completion });
}

pub fn read(
    self: *Loop,
    io: Io,
    completion: *Completion,
    callback: anytype,
    context: anytype,
    fd: posix.fd_t,
    buffer: []u8,
) !void {
    try self.concurrent(io, completion, callback, context, .read, .{
        .fd = fd,
        .buffer = buffer,
    }, struct {
        fn read(data: *Operation.Read) posix.ReadError!usize {
            return posix.read(data.fd, data.buffer);
        }
    }.read);
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
            @call(.auto, callback, .{ _context, _completion });
        }
    };

    completion.operation = .@"defer";
    completion.context = @ptrCast(@alignCast(context));
    completion.callback = TypeErased.complete;

    self.completions.push(completion);
}

pub const Operation = union(enum) {
    noop: void,
    @"defer": void,
    read: Read,
    machport: MachPort,

    pub const Read = struct {
        fd: posix.fd_t,
        buffer: []u8,
        result: posix.ReadError!usize = 0,
    };

    pub const MachPort = struct {
        port: posix.system.mach_port_name_t,
        buffer: []u8,
    };
};

pub const Completion = struct {
    const noop: Completion = .{
        .operation = .noop,
        .context = null,
        .callback = noopCallback,
        .prev = null,
        .next = null,
    };

    operation: Operation,
    context: ?*anyopaque,
    callback: *const CallbackFn,

    prev: ?*Completion = null,
    next: ?*Completion = null,

    pub const CallbackFn = fn (
        loop: *Loop,
        completion: *Completion,
    ) void;

    pub fn noopCallback(_: *Loop, _: *Completion) void {}
};

test "defer" {
    const io = testing.io;

    var loop: Loop = undefined;
    try loop.init();
    defer loop.deinit(io);

    var context: u64 = 0;
    var completion: Completion = .noop;

    loop.@"defer"(&completion, struct {
        pub fn @"defer"(_context: *u64, _: *Completion) void {
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

    const expected = "hello";
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(io, .{ .sub_path = "read.txt", .data = expected });
    const file = try tmp.dir.openFile(io, "read.txt", .{});
    defer file.close(io);

    var buffer: [expected.len]u8 = undefined;
    var completion: Completion = .noop;
    var context: struct {
        completed: bool = false,
        result: ?posix.ReadError!usize = null,
    } = .{};

    try loop.read(io, &completion, struct {
        fn read(_context: *@TypeOf(context), _: *Completion, result: posix.ReadError!usize) void {
            _context.completed = true;
            _context.result = result;
        }
    }.read, &context, file.handle, &buffer);

    try testing.expectEqual(false, context.completed);
    try testing.expectEqual(@as(?posix.ReadError!usize, null), context.result);

    try loop.run(.until_done);

    try testing.expectEqual(true, context.completed);
    const bytes_read = try context.result.?;
    try testing.expectEqual(expected.len, bytes_read);
    try testing.expectEqualStrings(expected, buffer[0..bytes_read]);
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
        fn machport(_called: *bool, _: *Completion, result: void) void {
            _ = result;
            _called.* = true;
        }
    }.machport, &called, .machport, .{
        .port = mach_port,
        .buffer = &buffer,
    }, struct {
        fn machport(_: *Operation.MachPort) void {}
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
