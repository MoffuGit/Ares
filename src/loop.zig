//This events loop uses as lefence libxev and tigerbeetle implementations
//Sources:
// - TigerBeetle: https://github.com/tigerbeetle/tigerbeetle/tree/main [LIBXEV]
// - Libxev: https://github.com/mitchellh/libxev [TIGERBEETLE]
const std = @import("std");
const assert = std.debug.assert;
const posix = std.posix;
const testing = std.testing;
const Io = std.Io;
const meta = std.meta;

const datastruct = @import("datastruct.zig");
const queue = datastruct.queue;
const mpsc = datastruct.mpsc;

pub const Loop = @This();

kq: posix.fd_t,

completions: mpsc.Intrusive(Completion),
submissions: mpsc.Intrusive(Completion),

group: Io.Group,

pub fn init(self: *Loop) !void {
    const kq = posix.system.kqueue();
    self.* = .{
        .kq = kq,
        .completions = undefined,
        .submissions = undefined,
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
    try self.flush(mode == .no_wait);
}

pub fn flush(self: *Loop, no_wait: bool) !void {
    while (true) {
        var flushed = false;

        while (self.completions.pop()) |completion| {
            flushed = true;
            completion.callback(self, completion);
        }

        if (no_wait or self.group.state == 0) break;
        if (!flushed) std.Thread.yield() catch {};
    }
}

pub fn submit(
    self: *Loop,
    completion: *Completion,
    callback: anytype,
    context: anytype,
    operation: Operation,
) void {
    completion.* = .{
        .op = operation,
        .context = @ptrCast(@alignCast(context)),
        .callback = callback,
    };
    self.submissions.push(completion);
}

pub fn async(
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
        fn async(_: *Loop, _completion: *Completion) void {
            const result = @call(.auto, resolver, .{&@field(_completion.op, @tagName(op_tag))});

            const _context: Context = @ptrCast(@alignCast(_completion.context));

            @call(.auto, callback, .{ _context, _completion, result });
        }
    };

    self.submit(completion, TypeErased.async, context, @unionInit(Operation, @tagName(op_tag), op_data));
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
        .op = @unionInit(Operation, @tagName(op_tag), op_data),
        .context = @ptrCast(@alignCast(context)),
        .callback = undefined,
        .prev = null,
        .next = null,
    };

    const Context = @TypeOf(context);
    self.group.state += 1;

    const TypeErased = struct {
        fn concurrent(_loop: *Loop, _completion: *Completion) void {
            const data = &@field(_completion.op, @tagName(op_tag));
            data.result = @call(.auto, resolver, .{data});

            _completion.callback = complete;

            _loop.completions.push(_completion);
        }

        fn complete(_loop: *Loop, _completion: *Completion) void {
            const data = &@field(_completion.op, @tagName(op_tag));
            const _context: Context = @ptrCast(@alignCast(_completion.context));
            _loop.group.state -= 1;

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

    completion.op = .@"defer";
    completion.context = @ptrCast(@alignCast(context));
    completion.callback = TypeErased.complete;

    self.completions.push(completion);
}

pub const Operation = union(enum) {
    noop: void,
    @"defer": void,
    read: Read,

    pub const Read = struct {
        fd: posix.fd_t,
        buffer: []u8,
        result: posix.ReadError!usize = 0,
    };
};

pub const Completion = struct {
    const noop: Completion = .{
        .op = .noop,
        .context = null,
        .callback = noopCallback,
        .prev = null,
        .next = null,
    };

    op: Operation,
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
