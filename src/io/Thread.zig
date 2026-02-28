const std = @import("std");
const xev = @import("../global.zig").xev;
const xev_pkg = @import("xev");
const log = std.log.scoped(.io);

const Message = @import("message.zig").Message;
const BlockingQueue = @import("datastruct").BlockingQueue;
const Allocator = std.mem.Allocator;
const Io = @import("mod.zig");

pub const Mailbox = BlockingQueue(Message, 10);

pub const Thread = @This();

alloc: Allocator,
loop: xev.Loop,
thread_pool: *xev_pkg.ThreadPool,

io: *Io,
mailbox: *Mailbox,

wakeup: xev.Async,
wakeup_c: xev.Completion = .{},

stop: xev.Async,
stop_c: xev.Completion = .{},

pub fn init(alloc: Allocator, io: *Io) !Thread {
    const thread_pool = try alloc.create(xev_pkg.ThreadPool);
    thread_pool.* = xev_pkg.ThreadPool.init(.{});
    errdefer {
        thread_pool.shutdown();
        thread_pool.deinit();
        alloc.destroy(thread_pool);
    }

    var loop = try xev.Loop.init(.{ .thread_pool = thread_pool });
    errdefer loop.deinit();

    var wakeup_h = try xev.Async.init();
    errdefer wakeup_h.deinit();

    var mailbox = try Mailbox.create(alloc);
    errdefer mailbox.destroy(alloc);

    var stop_h = try xev.Async.init();
    errdefer stop_h.deinit();

    return .{
        .alloc = alloc,
        .loop = loop,
        .mailbox = mailbox,
        .thread_pool = thread_pool,
        .wakeup = wakeup_h,
        .stop = stop_h,
        .io = io,
    };
}

pub fn deinit(self: *Thread) void {
    self.wakeup.deinit();
    self.stop.deinit();
    self.loop.deinit();
    self.thread_pool.shutdown();
    self.thread_pool.deinit();
    self.alloc.destroy(self.thread_pool);
    self.mailbox.destroy(self.alloc);
}

pub fn threadMain(self: *Thread) void {
    self.threadMain_() catch |err| {
        log.err("error in worktree io thread err={}", .{err});
    };
}

fn threadMain_(self: *Thread) !void {
    defer log.debug("worktree io thread exited", .{});

    self.stop.wait(&self.loop, &self.stop_c, Thread, self, stopCallback);
    self.wakeup.wait(&self.loop, &self.wakeup_c, Thread, self, wakeupCallback);

    log.debug("starting worktree io thread", .{});
    defer log.debug("starting worktree io thread shutdown", .{});
    _ = try self.loop.run(.until_done);
}

fn stopCallback(
    self_: ?*Thread,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Async.WaitError!void,
) xev.CallbackAction {
    _ = r catch unreachable;
    log.debug("io stopCallback called, stopping loop", .{});
    self_.?.loop.stop();
    return .disarm;
}

fn wakeupCallback(
    self_: ?*Thread,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Async.WaitError!void,
) xev.CallbackAction {
    _ = r catch |err| {
        log.err("error in worktree io wakeup err={}", .{err});
        return .rearm;
    };

    const t = self_.?;

    t.drainMailbox() catch |err| {
        log.err("error draining io mailbox err={}", .{err});
    };

    return .rearm;
}

fn drainMailbox(self: *Thread) !void {
    while (self.mailbox.pop()) |message| {
        switch (message) {
            .read => |req| {
                req.init() catch continue;
                req.xev_file.read(
                    &self.loop,
                    &req.completion,
                    .{ .slice = req.buffer },
                    Io.ReadRequest,
                    req,
                    readCallback,
                );
            },
        }
    }
}

fn readCallback(
    req: ?*Io.ReadRequest,
    _: *xev.Loop,
    _: *xev.Completion,
    _: xev.File,
    _: xev.ReadBuffer,
    r: xev.ReadError!usize,
) xev.CallbackAction {
    const request = req orelse return .disarm;

    if (r) |bytes_read| {
        Io.onReadComplete(request, bytes_read);
    } else |err| {
        log.err("read error: {}", .{err});
        Io.onReadError(request);
    }

    return .disarm;
}
