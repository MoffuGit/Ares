pub const Thread = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.editor_thread);
const xev = @import("../global.zig").xev;
const BlockingQueue = @import("datastruct").BlockingQueue;
const messagepkg = @import("./Message.zig");
const SharedState = @import("../SharedState.zig");
const Editor = @import("../Editor.zig");

pub const Mailbox = BlockingQueue(messagepkg.Message, 64);

alloc: Allocator,

loop: xev.Loop,

wakeup: xev.Async,
wakeup_c: xev.Completion = .{},

stop: xev.Async,
stop_c: xev.Completion = .{},

mailbox: *Mailbox,

editor: *Editor,

pub fn init(alloc: Allocator, editor: *Editor) !Thread {
    var loop = try xev.Loop.init(.{});
    errdefer loop.deinit();

    var wakeup_h = try xev.Async.init();
    errdefer wakeup_h.deinit();

    var stop_h = try xev.Async.init();
    errdefer stop_h.deinit();

    var mailbox = try Mailbox.create(alloc);
    errdefer mailbox.destroy(alloc);

    return .{
        .alloc = alloc,
        .loop = loop,
        .wakeup = wakeup_h,
        .stop = stop_h,
        .mailbox = mailbox,
        .editor = editor,
    };
}

pub fn deinit(self: *Thread) void {
    self.stop.deinit();
    self.wakeup.deinit();
    self.mailbox.destroy(self.alloc);
}

pub fn threadMain(self: *Thread) void {
    self.threadMain_() catch |err| {
        log.warn("error in editor thread err={}", .{err});
    };
}

fn threadMain_(self: *Thread) !void {
    defer log.debug("editor thread exited", .{});

    self.wakeup.wait(&self.loop, &self.wakeup_c, Thread, self, wakeupCallback);
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
        log.err("error in wakeup err={}", .{err});
        return .rearm;
    };

    const t = self_.?;

    t.drainMailbox() catch |err|
        log.err("error draining mailbox err={}", .{err});

    return .rearm;
}

fn drainMailbox(self: *Thread) !void {
    while (self.mailbox.pop()) |message| {
        switch (message) {
            .buffer_update => {
                self.editor.writeScreen();
            },
            .select_entry => |id| {
                self.editor.selectSurfaceEntry(id);
            },
            .resize => |size| {
                self.editor.resize(size);
            },
            .scroll => |row| {
                self.editor.scroll(row);
            },
        }
    }
}
