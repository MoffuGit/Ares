pub const Loop = @This();

const std = @import("std");
const xev = @import("xev").Dynamic;
const vaxis = @import("vaxis");
const datastruct = @import("datastruct");
const log = std.log.scoped(.loop);

const BlockingQueue = datastruct.BlockingQueue;
const Allocator = std.mem.Allocator;

const App = @import("mod.zig");
const Window = @import("window/mod.zig");

const WindowMessage = Window.Message;
const AppMessage = App.Message;

pub const Message = union(enum) {
    window: WindowMessage,
    app: AppMessage,
};

pub const Mailbox = BlockingQueue(Message, 64);

alloc: Allocator,

loop: xev.Loop,

wakeup: xev.Async,
wakeup_c: xev.Completion = .{},

stop: xev.Async,
stop_c: xev.Completion = .{},

tick_h: xev.Timer,
tick_c: xev.Completion = .{},
tick_active: bool = false,

mailbox: *Mailbox,
app: *App,

pub fn init(alloc: Allocator, app: *App) !Loop {
    var loop = try xev.Loop.init(.{});
    errdefer loop.deinit();

    var wakeup_h = try xev.Async.init();
    errdefer wakeup_h.deinit();

    var stop_h = try xev.Async.init();
    errdefer stop_h.deinit();

    var tick_h = try xev.Timer.init();
    errdefer tick_h.deinit();

    var mailbox = try Mailbox.create(alloc);
    errdefer mailbox.destroy(alloc);

    return .{
        .alloc = alloc,
        .app = app,
        .tick_h = tick_h,
        .loop = loop,
        .stop = stop_h,
        .mailbox = mailbox,
        .wakeup = wakeup_h,
    };
}

pub fn deinit(self: *Loop) void {
    self.stop.deinit();
    self.tick_h.deinit();
    self.wakeup.deinit();
    self.mailbox.destroy(self.alloc);
    self.loop.deinit();
}

pub fn threadMain(self: *Loop) void {
    self.threadMain_() catch |err| {
        log.warn("error in loop err={}", .{err});
    };
}

pub fn threadMain_(self: *Loop) !void {
    defer log.debug("loop exited", .{});

    self.wakeup.wait(&self.loop, &self.wakeup_c, Loop, self, wakeupCallback);
    self.stop.wait(&self.loop, &self.stop_c, Loop, self, stopCallback);

    try self.wakeup.notify();

    log.debug("starting loop", .{});
    defer log.debug("starting loop shutdown", .{});
    _ = try self.loop.run(.until_done);
}

fn wakeupCallback(
    self_: ?*Loop,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Async.WaitError!void,
) xev.CallbackAction {
    _ = r catch |err| {
        log.err("error in wakeup err={}", .{err});
        return .rearm;
    };

    const l = self_.?;

    l.drainMailbox() catch |err|
        log.err("error draining mailbox err={}", .{err});

    if (l.app.on_wakeup) |cb| cb(l.app);

    l.app.drawWindow() catch |err|
        log.err("draw error: {}", .{err});

    return .rearm;
}

pub fn scheduleNextTick(self: *Loop) void {
    if (self.tick_active) return;

    if (self.app.window.time.peekNext() == null) {
        self.tick_active = false;
        return;
    }

    self.tick_active = true;

    self.tick_h.run(
        &self.loop,
        &self.tick_c,
        6,
        Loop,
        self,
        tickCallback,
    );
}

fn tickCallback(
    self_: ?*Loop,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Timer.RunError!void,
) xev.CallbackAction {
    _ = r catch {};
    const l: *Loop = self_ orelse {
        log.warn("tick callback fired without data set", .{});
        return .disarm;
    };

    l.tick_active = false;

    const now = std.time.microTimestamp();
    l.app.window.time.processDue(now) catch |err| {
        log.err("tick error: {}", .{err});
    };

    l.app.drawWindow() catch |err|
        log.err("draw error: {}", .{err});

    l.scheduleNextTick();

    return .disarm;
}

fn drainMailbox(self: *Loop) !void {
    while (self.mailbox.pop()) |message| {
        switch (message) {
            .window => |msg| {
                try self.app.window.handleMessage(msg);
            },
            .app => |msg| {
                try self.app.handleMessage(msg);
            },
        }
    }

    self.scheduleNextTick();
}

fn stopCallback(
    self_: ?*Loop,
    _: *xev.Loop,
    _: *xev.Completion,
    r: xev.Async.WaitError!void,
) xev.CallbackAction {
    _ = r catch unreachable;
    self_.?.loop.stop();
    return .disarm;
}
