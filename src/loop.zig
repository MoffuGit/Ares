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

pub const Loop = @This();

kq: posix.fd_t,
completions: queue.Intrusive(Completion),

pub fn init(self: *Loop) !void {
    const kq = posix.system.kqueue();
    self.* = .{
        .kq = kq,
        .completions = .{},
    };
}

pub fn deinit(self: *Loop) void {
    assert(self.kq > -1);
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

pub fn flush(self: *Loop, _: bool) !void {
    while (self.completions.pop()) |completion| {
        completion.callback(self, completion);
    }
}

pub fn submit(
    self: *Loop,
    completion: *Completion,
    callback: anytype,
    context: anytype,
    op_tag: meta.Tag(Operation),
    op_data: @FieldType(Operation, @tagName(op_tag)),
    resolver: anytype,
) !void {
    const Context = @TypeOf(context);

    const TypeErased = struct {
        fn complete(_: *Loop, _completion: *Completion) void {
            const data = &@field(_completion.op, @tagName(op_tag));
            const result = @call(.auto, resolver, .{data});

            const _context: Context = @ptrCast(@alignCast(_completion.context));

            @call(.auto, callback, .{ _context, _completion, result });
        }
    };

    completion.op = @unionInit(Operation, @tagName(op_tag), op_data);
    completion.context = @ptrCast(@alignCast(context));
    completion.callback = TypeErased.complete;

    self.completions.push(completion);
}

pub const Operation = union(enum) {
    noop: void,
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

    prev: ?*Completion,
    next: ?*Completion,

    pub const CallbackFn = fn (
        loop: *Loop,
        completion: *Completion,
    ) void;

    pub fn noopCallback(_: *Loop, _: *Completion) void {}
};

test "noop" {
    var loop: Loop = undefined;
    try loop.init();
    defer loop.deinit();

    var completion: Completion = .noop;
    var context: void = {};

    try loop.submit(
        &completion,
        struct {
            pub fn noop(_: *void, _: *Completion, _: void) void {}
        }.noop,
        &context,
        .noop,
        {},
        struct {
            pub fn noop(_: *void) void {}
        }.noop,
    );

    try loop.run(.no_wait);
}
