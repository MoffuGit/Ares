const std = @import("std");
const App = @import("app.zig");
const Context = App.Context;
const sch = @import("scheduler.zig");
const Waker = sch.Waker;
const BackgroundScheduler = sch.BackgroundScheduler;

pub const Workspace = @This();

timer: BackgroundScheduler.Cancelation,
waker: Waker,
count: usize,

pub fn init(self: *Workspace, ctx: Context(Workspace)) !void {
    self.* = .{
        .count = 0,
        .waker = undefined,
        .timer = undefined,
    };

    self.waker = try ctx.await(Workspace.increment, .{});

    const scheduler = ctx.scheduler();
    self.timer = try scheduler.timer(Workspace.tick, .{self.waker}, 1000);
}

pub fn deinit(self: *Workspace) void {
    self.timer.cancel();
    self.waker.close();
}

pub fn increment(ctx: Context(Workspace)) bool {
    const workspace, const update = ctx.update();
    defer update.end(workspace);

    workspace.count += 1;
    ctx.notify();

    return true;
}

pub fn tick(waker: Waker, res: anyerror!void) bool {
    res catch return false;
    waker.wake() catch return false;

    return true;
}
