const std = @import("std");
const Allocator = std.mem.Allocator;
const xev = @import("../global.zig").xev;
const BlockingQueue = @import("../datastruct/blocking_queue.zig").BlockingQueue;
const messagepkg = @import("./Message.zig");

const log = std.log.scoped(.worktree_thread);

pub const Thread = @This();

pub const Mailbox = BlockingQueue(messagepkg.Message, 64);

alloc: Allocator,
loop: xev.Loop,

mailbox: *Mailbox,

fs: xev.FileSystem,
fs_c: xev.FileSystem.Completion = .{},

wakeup: xev.Async,
wakeup_c: xev.Completion = .{},

stop: xev.Async,
stop_c: xev.Completion = .{},

current_path: []const u8 = "",

pub fn init(alloc: Allocator) !Thread {
    var loop = try xev.Loop.init(.{});
    errdefer loop.deinit();

    var mailbox = try Mailbox.create(alloc);
    errdefer mailbox.destroy(alloc);

    var wakeup_h = try xev.Async.init();
    errdefer wakeup_h.deinit();

    var stop_h = try xev.Async.init();
    errdefer stop_h.deinit();

    var fs_h = xev.FileSystem.init();
    errdefer fs_h.deinit();

    return .{ .alloc = alloc, .loop = loop, .mailbox = mailbox, .wakeup = wakeup_h, .stop = stop_h, .fs = fs_h };
}

pub fn deinit(self: *Thread) void {
    if (self.current_path.len > 0) {
        self.alloc.free(self.current_path);
    }
    self.fs.deinit();
    self.wakeup.deinit();
    self.stop.deinit();
    self.loop.deinit();
    self.mailbox.destroy(self.alloc);
}

pub fn threadMain(self: *Thread) void {
    self.threadMain_() catch |err| {
        log.err("error in worktree thread err={}", .{err});
    };
}

fn threadMain_(self: *Thread) !void {
    defer log.debug("worktree thread exited", .{});

    self.stop.wait(&self.loop, &self.stop_c, Thread, self, stopCallback);
    self.wakeup.wait(&self.loop, &self.wakeup_c, Thread, self, wakeupCallback);

    log.debug("starting worktree thread", .{});
    defer log.debug("starting worktree thread shutdown", .{});
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

fn fsEventsCallback(
    self: ?*Thread,
    _: *xev.FileSystem.Completion,
    _: []const u8,
    r: u32,
) xev.CallbackAction {
    const t = self.?;
    const event = r;

    log.info("FsEvent triggered in worktree path '{s}': type='{}'", .{ t.current_path, event });

    _ = t.mailbox.push(messagepkg.Message{ .fsevent = event }, .instant);

    t.wakeup.notify() catch |err| {
        log.err("Failed to notify worktree wakeup handle: {}", .{err});
    };

    return .rearm;
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

    _ = t.drainMailbox() catch |err| {
        log.err("error draining mailbox err={}", .{err});
    };

    return .rearm;
}

fn drainMailbox(self: *Thread) !bool {
    var processed_any = false;
    while (self.mailbox.pop()) |message| {
        processed_any = true;
        switch (message) {
            .fsevent => |event| {
                log.info("Processing FsEvent: type='{}'", .{event});
            },
            .pwd => |path_bytes| {
                log.debug("Received set_path message: '{s}'", .{path_bytes});
                self.setWorktreePath(path_bytes) catch |err| {
                    log.err("Failed to set worktree path to '{s}': {}", .{ path_bytes, err });
                };
                self.alloc.free(path_bytes);
            },
        }
    }
    return processed_any;
}

fn setWorktreePath(self: *Thread, path: []const u8) !void {
    if (self.current_path.len > 0) {
        self.alloc.free(self.current_path);
        self.current_path = "";
    }

    if (self.fs_c.state() == .active) {
        self.fs.cancel(&self.fs_c);
        self.fs_c = .{};
    }

    self.current_path = try self.alloc.dupe(u8, path);
    try self.fs.watch(&self.loop, self.current_path, &self.fs_c, Thread, self, fsEventsCallback);

    log.info("Worktree path set to: '{s}'", .{self.current_path});
}
