const std = @import("std");
const Allocator = std.mem.Allocator;
const xev = @import("xev").Dynamic;
const BlockingQueue = @import("datastruct").BlockingQueue;
const messagepkg = @import("./Message.zig");
const Scanner = @import("mod.zig");

const log = std.log.scoped(.worktree_scanner);

pub const Thread = @This();

pub const Mailbox = BlockingQueue(messagepkg.Message, 100);

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
    // No cleanup needed - messages are now ID-based (no owned strings)
    while (self.mailbox.pop()) |_| {}

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
    log.debug("scanner stopCallback called, stopping loop", .{});
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
    var fs_events = std.AutoHashMap(u64, u32).init(self.alloc);
    defer fs_events.deinit();

    while (self.mailbox.pop()) |message| {
        switch (message) {
            .scan_dir => |dir_id| {
                try self.scanner.process_scan_by_id(dir_id);
            },
            .initialScan => {
                try self.scanner.initial_scan();
            },
            .fsEvent => |data| {
                const entry = try fs_events.getOrPut(data.id);
                if (entry.found_existing) {
                    entry.value_ptr.* |= data.events;
                } else {
                    entry.value_ptr.* = data.events;
                }
            },
        }
    }

    if (fs_events.count() > 0) {
        const updated_entries = try self.scanner.process_events(&fs_events);

        // Send to app loop; if it fails, destroy the entries ourselves
        if (!self.scanner.worktree.notifyUpdatedEntries(updated_entries)) {
            updated_entries.destroy();
        }
    }
}
