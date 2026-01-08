const std = @import("std");
const Allocator = std.mem.Allocator;
const xev = @import("../../global.zig").xev;
const BlockingQueue = @import("../../datastruct/blocking_queue.zig").BlockingQueue;
const messagepkg = @import("./Message.zig");
const Scanner = @import("mod.zig");

const log = std.log.scoped(.worktree_scanner);

pub const Thread = @This();

pub const Mailbox = BlockingQueue(messagepkg.Message, 64);

alloc: Allocator,
loop: xev.Loop,

mailbox: *Mailbox,

scanner: *Scanner,

wakeup: xev.Async,
wakeup_c: xev.Completion = .{},

stop: xev.Async,
stop_c: xev.Completion = .{},

pub fn init(alloc: Allocator, scanner: *Scanner) !Thread {
    var loop = try xev.Loop.init(.{});
    errdefer loop.deinit();

    var mailbox = try Mailbox.create(alloc);
    errdefer mailbox.destroy(alloc);

    var wakeup_h = try xev.Async.init();
    errdefer wakeup_h.deinit();

    var stop_h = try xev.Async.init();
    errdefer stop_h.deinit();

    return .{ .alloc = alloc, .loop = loop, .mailbox = mailbox, .wakeup = wakeup_h, .stop = stop_h, .scanner = scanner };
}

pub fn deinit(self: *Thread) void {
    self.wakeup.deinit();
    self.stop.deinit();
    self.loop.deinit();
    self.mailbox.destroy(self.alloc);
}

pub fn threadMain(self: *Thread) void {
    self.threadMain_() catch |err| {
        log.err("error in worktree scanner thread err={}", .{err});
    };
}

fn threadMain_(self: *Thread) !void {
    defer log.debug("worktree thread exited", .{});

    self.stop.wait(&self.loop, &self.stop_c, Thread, self, stopCallback);
    self.wakeup.wait(&self.loop, &self.wakeup_c, Thread, self, wakeupCallback);

    log.debug("starting worktree scanner thread", .{});
    defer log.debug("starting worktree scanner thread shutdown", .{});
    _ = try self.loop.run(.until_done);
}

fn stopCallback(
    self_: ?*Thread,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Async.WaitError!void,
) xev.CallbackAction {
    _ = r catch unreachable;
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
        log.err("error in worktree wakeup err={}", .{err});
        return .rearm;
    };

    const t = self_.?;

    t.drainMailbox() catch |err| {
        log.err("error draining mailbox err={}", .{err});
    };

    return .rearm;
}

fn drainMailbox(self: *Thread) !void {
    while (self.mailbox.pop()) |message| {
        switch (message) {
            .scan => |request| {
                try self.scanner.process_scan_request(request.path, request.abs_path);
            },
            .initialScan => {
                try self.scanner.initial_scan();
            },
        }
    }
}
