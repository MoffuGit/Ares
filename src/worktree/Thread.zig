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

fs_events: ?xev.FsEvents,
fs_events_c: xev.Completion = .{},

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

    return .{
        .alloc = alloc,
        .loop = loop,
        .mailbox = mailbox,
        .fs_events = null,
        .wakeup = wakeup_h,
        .stop = stop_h,
    };
}

pub fn deinit(self: *Thread) void {
    if (self.fs_events) |fs| {
        fs.deinit();
    }
    if (self.current_path.len > 0) {
        self.alloc.free(self.current_path);
    }
    self.wakeup.deinit(); // Deinitialize wakeup handle
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

    // Arm the stop handler to allow the thread to be gracefully stopped.
    self.stop.wait(&self.loop, &self.stop_c, Thread, self, stopCallback);
    // Arm the wakeup handle to process mailbox messages
    self.wakeup.wait(&self.loop, &self.wakeup_c, Thread, self, wakeupCallback);

    log.debug("starting worktree thread", .{});
    defer log.debug("starting worktree thread shutdown", .{});
    _ = try self.loop.run(.until_done);
}

/// Callback for the stop Async handle, gracefully stops the event loop.
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

/// Callback for FsEvents, triggered when filesystem events occur.
fn fsEventsCallback(
    self: ?*Thread,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.FsEventError!xev.FsEvent,
) xev.CallbackAction {
    const t = self.?;
    const event = r catch |err| {
        log.err("FsEvent error for worktree path '{}': {}", .{ t.current_path, err });
        return .rearm;
    };

    log.info("FsEvent triggered in worktree path '{}': type='{}'", .{ t.current_path, event });

    // Push the event to the mailbox for processing.
    t.mailbox.put(messagepkg.Message{ .fs_event = event }) catch |err| {
        log.err("Failed to put FsEvent message into mailbox: {}", .{err});
    };

    // Notify the wakeup handle to drain the mailbox
    t.wakeup.notify() catch |err| {
        log.err("Failed to notify worktree wakeup handle: {}", .{err});
    };

    // To keep watching for events, return .rearm.
    return .rearm;
}

/// Callback for the wakeup Async handle, triggers mailbox draining.
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

    // Drain the mailbox.
    t.drainMailbox() catch |err| {
        log.err("error draining mailbox err={}", .{err});
    };

    // Always rearm the wakeup handle, as it waits for further notifications.
    return .rearm;
}

/// Drains messages from the mailbox and processes them according to their type.
/// Returns `true` if any messages were processed, `false` otherwise.
fn drainMailbox(self: *Thread) !bool {
    var processed_any = false;
    while (self.mailbox.pop()) |message| {
        processed_any = true;
        switch (message) {
            .fs_event => |event| {
                // Process the filesystem event here.
                log.info("Processing FsEvent: type='{}'", .{event});
                // Add actual worktree logic: e.g., invalidate caches, refresh file lists, etc.
            },
            .stop => {
                // Received a stop message, stop the event loop.
                log.debug("Received stop message, stopping worktree loop", .{});
                self.loop.stop();
                return true; // Indicate message processed.
            },
            .set_path => |path_bytes| {
                log.debug("Received set_path message: '{}'", .{path_bytes});
                self.setWorktreePath(path_bytes) catch |err| {
                    log.err("Failed to set worktree path to '{}': {}", .{path_bytes, err});
                };
                self.alloc.free(path_bytes);
            },
        }
    }
    return processed_any;
}

/// Sets up or updates the FsEvents watcher for a given path.
/// This function takes ownership of the `path` slice.
fn setWorktreePath(self: *Thread, path: []const u8) !void {
    // Deinitialize existing FsEvents watcher if one is active.
    if (self.fs_events) |fs| {
        fs.deinit();
        self.fs_events = null;
    }
    // Free the old owned path string if one was set.
    if (self.current_path.len > 0) {
        self.alloc.free(self.current_path);
        self.current_path = "";
    }

    // Duplicate the new path string to take ownership of it for the thread.
    self.current_path = try self.alloc.dupe(u8, path);

    // Initialize a new FsEvents watcher for the new path.
    const new_fs_events = try xev.FsEvents.init(self.current_path);
    self.fs_events = new_fs_events;

    // Arm the new FsEvents watcher to begin monitoring events.
    try self.fs_events.?.wait(&self.loop, &self.fs_events_c, Thread, self, fsEventsCallback);

    log.info("Worktree path set to: '{}'", .{self.current_path});
}
