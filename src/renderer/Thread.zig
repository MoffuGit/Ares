pub const Thread = @This();
const std = @import("std");
const Allocator = std.mem.Allocator;
const apprt = @import("../apprt/embedded.zig");
const rendererpkg = @import("../renderer.zig");
const log = std.log.scoped(.renderer_thread);
const xev = @import("../global.zig").xev;

const DRAW_INTERVAL = 8; // 120 FPS

alloc: Allocator,

loop: xev.Loop,

draw_h: xev.Timer,
draw_c: xev.Completion = .{},

stop: xev.Async,
stop_c: xev.Completion = .{},

surface: *apprt.Surface,
renderer: *rendererpkg.Renderer,

pub fn init(
    alloc: Allocator,
    surface: *apprt.Surface,
    renderer_impl: *rendererpkg.Renderer,
) !Thread {
    var loop = try xev.Loop.init(.{});
    errdefer loop.deinit();

    var draw_h = try xev.Timer.init();
    errdefer draw_h.deinit();

    var stop_h = try xev.Async.init();
    errdefer stop_h.deinit();

    return .{ .alloc = alloc, .surface = surface, .renderer = renderer_impl, .loop = loop, .draw_h = draw_h, .stop = stop_h };
}

pub fn deinit(self: *Thread) void {
    self.draw_h.deinit();
    self.stop.deinit();
}

pub fn threadMain(self: *Thread) void {
    self.threadMain_() catch |err| {
        log.warn("error in renderer err={}", .{err});
    };
}

fn threadMain_(self: *Thread) !void {
    defer log.debug("renderer thread exited", .{});

    const has_loop = @hasDecl(rendererpkg.Renderer, "loopEnter");
    if (has_loop) try self.renderer.api.loopEnter(self);

    self.stop.wait(&self.loop, &self.stop_c, Thread, self, stopCallback);

    try self.startDrawTimer();

    log.debug("starting renderer thread", .{});
    defer log.debug("starting renderer thread shutdown", .{});
    _ = try self.loop.run(.until_done);
}

fn startDrawTimer(self: *Thread) !void {
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

    t.drawFrame();

    t.draw_h.run(&t.loop, &t.draw_c, DRAW_INTERVAL, Thread, t, drawCallback);

    return .disarm;
}

fn drawFrame(self: *Thread) void {
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
