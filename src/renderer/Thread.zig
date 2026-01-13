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

const DRAW_INTERVAL = 8;

alloc: Allocator,

loop: xev.Loop,

wakeup: xev.Async,
wakeup_c: xev.Completion = .{},

draw_h: xev.Timer,
draw_c: xev.Completion = .{},

stop: xev.Async,
stop_c: xev.Completion = .{},

draw_now: xev.Async,
draw_now_c: xev.Completion = .{},

mailbox: *Mailbox,

renderer: *Renderer,

pub fn init(alloc: Allocator, renderer: *Renderer) !Thread {
    var loop = try xev.Loop.init(.{});
    errdefer loop.deinit();

    var draw_h = try xev.Timer.init();
    errdefer draw_h.deinit();

    var wakeup_h = try xev.Async.init();
    errdefer wakeup_h.deinit();

    var draw_now = try xev.Async.init();
    errdefer draw_now.deinit();

    var stop_h = try xev.Async.init();
    errdefer stop_h.deinit();

    var mailbox = try Mailbox.create(alloc);
    errdefer mailbox.destroy(alloc);

    return .{ .alloc = alloc, .renderer = renderer, .draw_now = draw_now, .loop = loop, .draw_h = draw_h, .stop = stop_h, .mailbox = mailbox, .wakeup = wakeup_h };
}

pub fn deinit(self: *Thread) void {
    self.draw_h.deinit();
    self.stop.deinit();
    self.draw_now.deinit();
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
    self.draw_now.wait(&self.loop, &self.draw_now_c, Thread, self, drawNowCallback);

    try self.wakeup.notify();
    self.startDrawTimer();

    log.debug("starting renderer thread", .{});
    defer log.debug("starting renderer thread shutdown", .{});
    _ = try self.loop.run(.until_done);
}

fn drawNowCallback(
    self_: ?*Thread,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Async.WaitError!void,
) xev.CallbackAction {
    _ = r catch |err| {
        log.err("error in draw now err={}", .{err});
        return .rearm;
    };

    const t = self_.?;
    t.renderer.drawFrame(false) catch |err|
        log.warn("error drawing err={}", .{err});

    return .rearm;
}

fn startDrawTimer(self: *Thread) void {
    self.draw_h.run(
        &self.loop,
        &self.draw_c,
        DRAW_INTERVAL,
        Thread,
        self,
        drawCallback,
    );
}

fn drawCallback(
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

    t.renderer.drawFrame(false) catch |err|
        log.warn("error drawing err={}", .{err});

    t.draw_h.run(&t.loop, &t.draw_c, DRAW_INTERVAL, Thread, t, drawCallback);

    return .disarm;
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

    t.renderer.drawFrame(false) catch |err|
        log.warn("error drawing err={}", .{err});

    return .disarm;
}

fn drainMailbox(self: *Thread) !void {
    while (self.mailbox.pop()) |message| {
        _ = message;
    }
}
