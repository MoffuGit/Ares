pub const Thread = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const rendererpkg = @import("../Renderer.zig");
const log = std.log.scoped(.renderer_thread);
const xev = @import("../global.zig").xev;
const BlockingQueue = @import("datastruct").BlockingQueue;
const messagepkg = @import("./Message.zig");

pub const Mailbox = BlockingQueue(messagepkg.Message, 64);

const DRAW_INTERVAL = 8; // 120 FPS

alloc: Allocator,

loop: xev.Loop,

flags: packed struct {
    /// This is true when the view is visible. This is used to determine
    /// if we should be rendering or not.
    visible: bool = true,
} = .{},

wakeup: xev.Async,
wakeup_c: xev.Completion = .{},

draw_h: xev.Timer,
draw_c: xev.Completion = .{},

stop: xev.Async,
stop_c: xev.Completion = .{},

draw_now: xev.Async,
draw_now_c: xev.Completion = .{},

renderer: *rendererpkg.Renderer,

mailbox: *Mailbox,

pub fn init(alloc: Allocator, renderer: *rendererpkg.Renderer) !Thread {
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

    return .{ .alloc = alloc, .draw_now = draw_now, .renderer = renderer, .loop = loop, .draw_h = draw_h, .stop = stop_h, .mailbox = mailbox, .wakeup = wakeup_h };
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

    try self.renderer.loopEnter(self);
    defer self.renderer.loopExit(self);

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

    // Draw immediately
    const t = self_.?;
    t.drawFrame(true);

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

    t.drawFrame(false);

    t.draw_h.run(&t.loop, &t.draw_c, DRAW_INTERVAL, Thread, t, drawCallback);

    return .disarm;
}

fn drawFrame(self: *Thread, now: bool) void {
    if (!self.flags.visible) return;
    if (!now and self.renderer.hasVsync()) return;

    self.renderer.drawFrame(false) catch |err|
        log.warn("error drawing err={}", .{err});
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

    // Update our frame data
    t.renderer.updateFrame() catch |err|
        log.warn("error rendering err={}", .{err});

    // Draw
    t.drawFrame(false);

    return .disarm;
}

pub const SetQosClassError = error{
    // The thread can't have its QoS class changed usually because
    // a different pthread API was called that makes it an invalid
    // target.
    ThreadIncompatible,
};

pub const QosClass = enum(c_uint) {
    user_interactive = 0x21,
    user_initiated = 0x19,
    default = 0x15,
    utility = 0x11,
    background = 0x09,
    unspecified = 0x00,
};

extern "c" fn pthread_set_qos_class_self_np(
    qos_class: QosClass,
    relative_priority: c_int,
) c_int;

/// Set the QoS class of the running thread.
///
/// https://developer.apple.com/documentation/apple-silicon/tuning-your-code-s-performance-for-apple-silicon?preferredLanguage=occ
pub fn internalSetQosClass(class: QosClass) !void {
    return switch (std.posix.errno(pthread_set_qos_class_self_np(
        class,
        0,
    ))) {
        .SUCCESS => {},
        .PERM => error.ThreadIncompatible,

        // EPERM is the only known error that can happen based on
        // the man pages for pthread_set_qos_class_self_np. I haven't
        // checked the XNU source code to see if there are other
        // possible errors.
        else => @panic("unexpected pthread_set_qos_class_self_np error"),
    };
}

fn setQosClass(self: *const Thread) void {
    // Thread QoS classes are only relevant on macOS.
    const class: QosClass = class: {
        // If we aren't visible (our view is fully occluded) then we
        // always drop our rendering priority down because it's just
        // mostly wasted work.
        //
        // The renderer itself should be doing this as well (for example
        // Metal will stop our DisplayLink) but this also helps with
        // general forced updates and CPU usage i.e. a rebuild cells call.
        if (!self.flags.visible) break :class .utility;

        // // If we're not focused, but we're visible, then we set a higher
        // // than default priority because framerates still matter but it isn't
        // // as important as when we're focused.
        // if (!self.flags.focused) break :class .user_initiated;

        // We are focused and visible, we are the definition of user interactive.
        break :class .user_interactive;
    };

    if (internalSetQosClass(class)) {
        log.debug("thread QoS class set class={}", .{class});
    } else |err| {
        log.warn("error setting QoS class err={}", .{err});
    }
}

fn drainMailbox(self: *Thread) !void {
    // There's probably a more elegant way to do this...
    //
    // This is effectively an @autoreleasepool{} block, which we need in
    // order to ensure that autoreleased objects are properly released.
    const pool = @import("objc").AutoreleasePool.init();
    defer pool.deinit();

    while (self.mailbox.pop()) |message| {
        switch (message) {
            .visible => |v| visible: {
                if (self.flags.visible == v) break :visible;

                self.flags.visible = v;

                self.setQosClass();

                if (v) self.drawFrame(false);

                self.renderer.setVisible(v);
            },
            .themeUpdate => {
                const color = self.renderer.settings.readThemeTextColor();
                self.renderer.setTextColor(color);
            },
            .resize => |size| {
                self.renderer.setScreenSize(size);
            },
        }
    }
}
