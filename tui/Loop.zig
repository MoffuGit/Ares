pub const Loop = @This();

const std = @import("std");
const xev = @import("xev").Dynamic;
const vaxis = @import("vaxis");
const datastruct = @import("datastruct");
const log = std.log.scoped(.loop);
const global = @import("global.zig");

const BlockingQueue = datastruct.BlockingQueue;
const Allocator = std.mem.Allocator;

const App = @import("App.zig");

pub const Message = union(enum) {
    scheme: vaxis.Color.Scheme,
    resize: vaxis.Winsize,
    key_press: vaxis.Key,
    key_release: vaxis.Key,
    focus: void,
    blur: void,
    mouse: vaxis.Mouse,
};

pub const Mailbox = BlockingQueue(Message, 64);

alloc: Allocator,

loop: xev.Loop,

wakeup: xev.Async,
wakeup_c: xev.Completion = .{},

stop: xev.Async,
stop_c: xev.Completion = .{},

mailbox: *Mailbox,
app: *App,

pub fn init(alloc: Allocator, app: *App) !Loop {
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
        .app = app,
        .loop = loop,
        .stop = stop_h,
        .mailbox = mailbox,
        .wakeup = wakeup_h,
    };
}

pub fn deinit(self: *Loop) void {
    self.stop.deinit();
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

    const winsize = try vaxis.Tty.getWinsize(self.app.shared_context.tty.fd);
    self.app.window.resize(winsize);
    global.state.bus.push(.resize, 0, .{ .resize = .{ .cols = winsize.cols, .rows = winsize.rows } });

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

    l.app.drawWindow() catch |err|
        log.err("draw error: {}", .{err});

    return .rearm;
}

fn drainMailbox(self: *Loop) !void {
    const bus = &global.state.bus;
    while (self.mailbox.pop()) |message| {
        switch (message) {
            .scheme => |scheme| {
                bus.push(.scheme, 0, .{ .scheme = .{ .scheme = @intFromEnum(scheme) } });
            },
            .resize => |size| {
                self.app.window.resize(size);
                bus.push(.resize, 0, .{ .resize = .{ .cols = size.cols, .rows = size.rows } });
            },
            .key_press => |key| {
                self.app.window.resolveKeyEvent(key, .key_down, bus);
            },
            .key_release => |key| {
                self.app.window.resolveKeyEvent(key, .key_up, bus);
            },
            .focus => {
                bus.push(.focus, 0, .{ .none = {} });
            },
            .blur => {
                bus.push(.blur, 0, .{ .none = {} });
            },
            .mouse => |mouse| {
                self.app.window.resolveMouseEvent(mouse, bus);
            },
        }
    }
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
