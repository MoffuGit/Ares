const std = @import("std");
const vaxis = @import("vaxis");
const builtin = @import("builtin");
const posix = std.posix;

const Screen = @import("Screen.zig");

const RendererThread = @import("renderer/Thread.zig");
const Renderer = @import("renderer/mod.zig");

const Loop = @import("Loop.zig");

const EventsThread = @import("events/Thread.zig");

const Scene = @import("Scene.zig");

const TimeManager = @import("TimeManager.zig");
const AppContext = @import("AppContext.zig");

const log = std.log.scoped(.app);

const Allocator = std.mem.Allocator;

pub const State = enum {
    idle,
    active,
    paused,
    cancelled,
    completed,
};

const App = @This();

var tty_buffer: [1024]u8 = undefined;

alloc: Allocator,
tty: vaxis.Tty,

events_thread: EventsThread,
events_thr: std.Thread,

screen: Screen,
renderer: Renderer,
renderer_thread: RendererThread,
renderer_thr: std.Thread,

loop: Loop,

time: TimeManager,

scene: Scene,

pub fn create(alloc: Allocator) !*App {
    var self = try alloc.create(App);

    var screen = try Screen.init(alloc, .{ .cols = 0, .rows = 0, .x_pixel = 0, .y_pixel = 0 });
    errdefer screen.deinit(alloc);

    var renderer = try Renderer.init(alloc, &self.tty, &self.screen);
    errdefer renderer.deinit();

    var renderer_thread = try RendererThread.init(alloc, &self.renderer);
    errdefer renderer_thread.deinit();

    var loop = try Loop.init(alloc, self);
    errdefer loop.deinit();

    var tty = try vaxis.Tty.init(&tty_buffer);
    self.tty = tty;
    errdefer tty.deinit();

    const events_thread = EventsThread.init(alloc, &self.tty, loop.mailbox, loop.wakeup);

    var time = TimeManager.init(alloc);
    errdefer time.deinit();

    var scene = try Scene.init(alloc);
    errdefer scene.deinit();

    self.* = .{
        .alloc = alloc,
        .screen = screen,
        .renderer = renderer,
        .renderer_thread = renderer_thread,
        .renderer_thr = undefined,
        .tty = tty,
        .loop = loop,
        .events_thread = events_thread,
        .events_thr = undefined,
        .time = time,
        .scene = scene,
    };

    const app_context: AppContext = .{
        .mailbox = self.loop.mailbox,
        .wakeup = self.loop.wakeup,
        .needs_draw = &self.scene.needs_draw,
    };
    self.scene.setContext(app_context);

    self.events_thr = try std.Thread.spawn(.{}, EventsThread.threadMain, .{&self.events_thread});
    self.renderer_thr = try std.Thread.spawn(.{}, RendererThread.threadMain, .{&self.renderer_thread});

    return self;
}

pub fn destroy(self: *App) void {
    {
        self.renderer_thread.stop.notify() catch |err| {
            log.err("error notifying renderer thread to stop, may stall err={}", .{err});
        };
        self.renderer_thr.join();
    }

    {
        self.events_thread.stop();
        self.events_thr.join();
    }

    self.renderer_thread.deinit();
    self.loop.deinit();

    self.scene.deinit();
    self.time.deinit();

    self.renderer.deinit();
    self.screen.deinit(self.alloc);
}

pub fn run(self: *App) !void {
    const winsize = try vaxis.Tty.getWinsize(self.tty.fd);

    self.scene.resize(winsize);

    try self.loop.wakeup.notify();

    self.loop.run();
}

pub fn draw(self: *App) !void {
    if (!self.scene.needsDraw()) return;
    self.scene.markDrawn();

    const screen = &self.screen;
    const buffer = screen.writeBuffer();

    const size = self.scene.size;
    if (buffer.width != size.cols or buffer.height != size.rows) {
        try screen.resizeWriteBuffer(self.alloc, size);
    }

    try self.scene.update();
    self.scene.draw(screen.writeBuffer());

    screen.swapWrite();

    try self.renderer_thread.wakeup.notify();
}

pub fn resize(self: *App, size: vaxis.Winsize) void {
    self.scene.resize(size);
}
