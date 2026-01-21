pub const Thread = @This();

const std = @import("std");
const xev = @import("../global.zig").xev;
const vaxis = @import("vaxis");
const BlockingQueue = @import("../datastruct/blocking_queue.zig").BlockingQueue;
const Renderer = @import("mod.zig");

const Allocator = std.mem.Allocator;

pub const Message = union(enum) { resize: vaxis.Winsize };

pub const Mailbox = BlockingQueue(Message, 64);

const log = std.log.scoped(.renderer_thread);

alloc: Allocator,

loop: xev.Loop,

wakeup: xev.Async,
wakeup_c: xev.Completion = .{},

stop: xev.Async,
stop_c: xev.Completion = .{},

mailbox: *Mailbox,

renderer: *Renderer,

pub fn init(alloc: Allocator, renderer: *Renderer) !Thread {
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
        .renderer = renderer,
        .loop = loop,
        .stop = stop_h,
        .mailbox = mailbox,
        .wakeup = wakeup_h,
    };
}

pub fn deinit(self: *Thread) void {
    self.stop.deinit();
    self.wakeup.deinit();
    self.mailbox.destroy(self.alloc);
}

pub fn threadMain(self: *Thread) void {
    self.threadMain_() catch |err| {
        log.warn("error in renderer err={}", .{err});
    };
}

fn threadMain_(self: *Thread) !void {
    defer log.debug("renderer thread exited", .{});

    try self.renderer.threadEnter();
    defer self.renderer.threadExit();

    self.wakeup.wait(&self.loop, &self.wakeup_c, Thread, self, wakeupCallback);
    self.stop.wait(&self.loop, &self.stop_c, Thread, self, stopCallback);

    try self.wakeup.notify();

    log.debug("starting renderer thread", .{});
    defer log.debug("starting renderer thread shutdown", .{});
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

    // When we wake up, we check the mailbox. Mailbox producers should
    // wake up our thread after publishing.
    t.drainMailbox() catch |err|
        log.err("error draining mailbox err={}", .{err});

    _ = renderCallback(t, undefined, undefined, {});

    return .rearm;
}

fn renderCallback(
    self_: ?*Thread,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Timer.RunError!void,
) xev.CallbackAction {
    _ = r catch unreachable;
    const t: *Thread = self_ orelse {
        // This shouldn't happen so we log it.
        log.warn("render callback fired without data set", .{});
        return .disarm;
    };

    t.renderer.renderFrame() catch |err|
        log.warn("error rendering err={}", .{err});

    return .disarm;
}

fn drainMailbox(self: *Thread) !void {
    while (self.mailbox.pop()) |message| {
        switch (message) {
            .resize => |size| {
                try self.renderer.resize(size);
            },
        }
    }
}
