pub const Thread = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const xev = @import("../global.zig").xev;
const BlockingQueue = @import("../datastruct/blocking_queue.zig").BlockingQueue;
const messagepkg = @import("./Message.zig");
const Editor = @import("../editor/mod.zig");

const log = std.log.scoped(.editor_thread);

pub const Mailbox = BlockingQueue(messagepkg.Message, 64);

alloc: Allocator,

loop: xev.Loop,

wakeup: xev.Async,
wakeup_c: xev.Completion = .{},

stop: xev.Async,
stop_c: xev.Completion = .{},

mailbox: *Mailbox,

editor: *Editor,

pub fn init(
    alloc: Allocator,
    editor: *Editor,
) !Thread {
    var loop = try xev.Loop.init(.{});
    errdefer loop.deinit();

    var stop_h = try xev.Async.init();
    errdefer stop_h.deinit();

    var wakeup_h = try xev.Async.init();
    errdefer wakeup_h.deinit();

    var mailbox = try Mailbox.create(alloc);
    errdefer mailbox.destroy(alloc);

    return .{ .alloc = alloc, .loop = loop, .stop = stop_h, .wakeup = wakeup_h, .mailbox = mailbox, .editor = editor };
}

pub fn deinit(self: *Thread) void {
    self.stop.deinit();
    self.wakeup.deinit();
    self.loop.deinit();
    self.mailbox.destroy(self.alloc);
}

pub fn threadMain(self: *Thread) void {
    self.threadMain_() catch |err| {
        log.err("error in editor thread err={}", .{err});
    };
}

fn threadMain_(self: *Thread) !void {
    defer log.debug("editor thread exited", .{});

    self.stop.wait(&self.loop, &self.stop_c, Thread, self, stopCallback);
    self.wakeup.wait(&self.loop, &self.wakeup_c, Thread, self, wakeupCallback);

    try self.wakeup.notify();

    log.debug("starting editor thread", .{});
    defer log.debug("starting editor thread shutdown", .{});
    _ = try self.loop.run(.until_done);
}

fn wakeupCallback(
    self_: ?*Thread,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Async.WaitError!void,
) xev.CallbackAction {
    _ = r catch |err| {
        log.err("error in wakeup err={}", .{err});
        return .rearm;
    };

    const t = self_.?;

    // When we wake up, we check the mailbox. Mailbox producers should
    // wake up our thread after publishing.
    t.drainMailbox() catch |err|
        log.err("error draining mailbox err={}", .{err});

    return .rearm;
}

fn drainMailbox(self: *Thread) !void {
    while (self.mailbox.pop()) |message| {
        switch (message) {
            .size => |size| {
                self.editor.resize(size);
            },
        }
    }
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
