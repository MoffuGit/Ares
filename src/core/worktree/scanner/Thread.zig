const std = @import("std");
const Allocator = std.mem.Allocator;
const xev = @import("../../global.zig").xev;
const BlockingQueue = @import("datastruct").BlockingQueue;
const messagepkg = @import("./Message.zig");
const Scanner = @import("mod.zig");

const log = std.log.scoped(.worktree_scanner);

pub const Thread = @This();

pub const Mailbox = BlockingQueue(messagepkg.Message, 100);

const FLUSH_INTERVAL_MS = 100;

alloc: Allocator,
loop: xev.Loop,

mailbox: *Mailbox,

scanner: *Scanner,

wakeup: xev.Async,
wakeup_c: xev.Completion = .{},

stop: xev.Async,
stop_c: xev.Completion = .{},

flush_timer: xev.Timer,
flush_timer_c: xev.Completion = .{},

pub fn init(alloc: Allocator, scanner: *Scanner) !Thread {
    var loop = try xev.Loop.init(.{});
    errdefer loop.deinit();

    var mailbox = try Mailbox.create(alloc);
    errdefer mailbox.destroy(alloc);

    var wakeup_h = try xev.Async.init();
    errdefer wakeup_h.deinit();

    var stop_h = try xev.Async.init();
    errdefer stop_h.deinit();

    var flush_timer = try xev.Timer.init();
    errdefer flush_timer.deinit();

    return .{ .alloc = alloc, .loop = loop, .mailbox = mailbox, .wakeup = wakeup_h, .stop = stop_h, .flush_timer = flush_timer, .scanner = scanner };
}

pub fn deinit(self: *Thread) void {
    self.flush_timer.deinit();
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
    self.scheduleFlushTimer();

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
    log.debug("scanner stopCallback called, stopping loop", .{});
    self_.?.loop.stop();
    return .disarm;
}

fn scheduleFlushTimer(self: *Thread) void {
    self.flush_timer.run(
        &self.loop,
        &self.flush_timer_c,
        FLUSH_INTERVAL_MS,
        Thread,
        self,
        flushTimerCallback,
    );
}

fn flushTimerCallback(
    self_: ?*Thread,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Timer.RunError!void,
) xev.CallbackAction {
    _ = r catch |err| {
        log.err("flush timer error: {}", .{err});
        return .disarm;
    };

    const self = self_.?;
    self.processDirtyEntries();
    self.scheduleFlushTimer();
    return .disarm;
}

fn processDirtyEntries(self: *Thread) void {
    var entries: std.ArrayList(u64) = .{};
    defer entries.deinit(self.alloc);

    {
        self.scanner.mutex.lock();
        defer self.scanner.mutex.unlock();
        entries.appendSlice(self.alloc, self.scanner.dirty_entries.items) catch return;
        self.scanner.dirty_entries.clearRetainingCapacity();
    }

    if (entries.items.len == 0) return;

    const result = self.scanner.process_events(entries.items) catch |err| {
        log.err("error processing dirty entries: {}", .{err});
        return;
    };

    // TODO: deliver result to consumer
    _ = result;
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
            .scan_dir => |dir_id| {
                try self.scanner.process_scan_by_id(dir_id);
            },
            .initialScan => {
                try self.scanner.initial_scan();
            },
        }
    }
}
