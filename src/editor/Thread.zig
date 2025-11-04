pub const Thread = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const xev = @import("../global.zig").xev;
const log = std.log.scoped(.editor_thread);

alloc: Allocator,

loop: xev.Loop,

stop: xev.Async,
stop_c: xev.Completion = .{},

pub fn init(
    alloc: Allocator,
) !Thread {
    var loop = try xev.Loop.init(.{});
    errdefer loop.deinit();

    var stop_h = try xev.Async.init();
    errdefer stop_h.deinit();

    return .{
        .alloc = alloc,
        .loop = loop,
        .stop = stop_h,
    };
}

pub fn deinit(self: *Thread) void {
    self.stop.deinit();
    self.loop.deinit();
}

pub fn threadMain(self: *Thread) void {
    self.threadMain_() catch |err| {
        log.err("error in editor thread err={}", .{err});
    };
}

fn threadMain_(self: *Thread) !void {
    defer log.debug("editor thread exited", .{});

    self.stop.wait(&self.loop, &self.stop_c, Thread, self, stopCallback);

    log.debug("starting editor thread", .{});
    defer log.debug("starting editor thread shutdown", .{});
    _ = try self.loop.run(.until_done);
}

fn stopCallback(
    self_: ?*Thread,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Async.WaitError!void,
) xev.CallbackAction {
    _ = r catch unreachable; // Should not happen for a simple stop
    self_.?.loop.stop();
    return .disarm;
}
