const std = @import("std");
const Allocator = std.mem.Allocator;
const xev = @import("../global.zig").xev;
const BlockingQueue = @import("../datastruct/blocking_queue.zig").BlockingQueue;
const messagepkg = @import("./Message.zig");

//WARN:
//i forgot to give me access to
//the FS completions
//and probably watch can accept more data like the callback and the userdata
//and set that for me into the completion
//
//then, once this is done,
//i need to store the fs completion for the directory or file we are waching
//and using it for cancelling when changing the watched directory
//any of that is hard
//after that
//i need to check what zed do for this worktree and try to make something similar
//on my case every time an event is triggered i will call for a file system pass and check what change
//from my prev snapshot to the new state, once that finish i need to pass the new data to the ui
//and update whatever my ui is

const log = std.log.scoped(.worktree_thread);

pub const Thread = @This();

pub const Mailbox = BlockingQueue(messagepkg.Message, 64);

alloc: Allocator,
loop: xev.Loop,

mailbox: *Mailbox,

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
        .wakeup = wakeup_h,
        .stop = stop_h,
    };
}

pub fn deinit(self: *Thread) void {
    if (self.current_path.len > 0) {
        self.alloc.free(self.current_path);
    }
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

// fn fsEventsCallback(
//     self: ?*Thread,
//     _: *xev.Loop,
//     _: *xev.Completion,
//     r: u32,
// ) xev.CallbackAction {
//     const t = self.?;
//     const event = r catch |err| {
//         log.err("FsEvent error for worktree path '{s}': {}", .{ t.current_path, err });
//         return .rearm;
//     };
//
//     log.info("FsEvent triggered in worktree path '{s}': type='{}'", .{ t.current_path, event });
//
//     _ = t.mailbox.push(messagepkg.Message{ .fsevent = event }, .instant);
//
//     t.wakeup.notify() catch |err| {
//         log.err("Failed to notify worktree wakeup handle: {}", .{err});
//     };
//
//     return .rearm;
// }

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

    self.current_path = try self.alloc.dupe(u8, path);

    log.info("Worktree path set to: '{s}'", .{self.current_path});
}
