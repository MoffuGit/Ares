const std = @import("std");
const vaxis = @import("vaxis");
const log = std.log.scoped(.app);

const Allocator = std.mem.Allocator;

const SharedContext = @import("SharedContext.zig");
const Screen = @import("Screen.zig");

const Loop = @import("Loop.zig");

const TtyThread = @import("TtyThread.zig");

const Renderer = @import("renderer/mod.zig");
const RendererThread = @import("renderer/Thread.zig");

const Window = @import("window/mod.zig");

const App = @This();

alloc: Allocator,

shared_context: SharedContext,
tty_thread: TtyThread,
tty_thr: std.Thread,

screen: Screen,
renderer: Renderer,
renderer_thread: RendererThread,
renderer_thr: std.Thread,

loop: Loop,
loop_thr: std.Thread,

window: Window,
draw: std.atomic.Value(bool) = .init(true),

pub fn create(alloc: Allocator) !*App {
    const app = try alloc.create(App);

    var screen = try Screen.init(alloc, .{
        .cols = 0,
        .rows = 0,
        .x_pixel = 0,
        .y_pixel = 0,
    });
    errdefer screen.deinit();

    var shared_context = try SharedContext.init(alloc);
    errdefer shared_context.deinit(alloc);

    var loop = try Loop.init(alloc, app);
    errdefer loop.deinit();

    var window = try Window.init(
        alloc,
        &app.screen,
    );
    errdefer window.deinit();

    var tty_thread = TtyThread.init(alloc, &app.shared_context, &app.loop);
    _ = &tty_thread;

    var renderer = try Renderer.init(alloc, &app.shared_context, &app.screen);
    errdefer renderer.deinit();

    var renderer_thread = try RendererThread.init(alloc, &app.renderer);
    errdefer renderer_thread.deinit();

    app.* = .{
        .alloc = alloc,
        .shared_context = shared_context,
        .loop = loop,
        .loop_thr = undefined,
        .screen = screen,
        .window = window,
        .tty_thread = tty_thread,
        .tty_thr = undefined,
        .renderer = renderer,
        .renderer_thread = renderer_thread,
        .renderer_thr = undefined,
    };

    app.loop_thr = try std.Thread.spawn(.{}, Loop.threadMain, .{&app.loop});
    app.tty_thr = try std.Thread.spawn(.{}, TtyThread.threadMain, .{&app.tty_thread});
    app.renderer_thr = try std.Thread.spawn(.{}, RendererThread.threadMain, .{&app.renderer_thread});

    return app;
}

pub fn destroy(self: *App) void {
    {
        self.tty_thread.stop();
        const writer = self.shared_context.tty.writer();
        writer.writeAll(vaxis.ctlseqs.device_status_report) catch {};
        writer.flush() catch {};
        self.tty_thr.join();
    }

    {
        self.renderer_thread.stop.notify() catch |err| {
            log.err("error notifying renderer thread to stop, may stall err={}", .{err});
        };
        self.renderer_thr.join();
    }

    {
        self.loop.stop.notify() catch |err| {
            log.err("error notifying renderer thread to stop, may stall err={}", .{err});
        };
        self.loop_thr.join();
    }

    self.renderer_thread.deinit();

    self.loop.deinit();

    self.window.deinit();
    self.renderer.deinit();

    self.screen.deinit();
    self.shared_context.deinit(self.alloc);
    self.alloc.destroy(self);
}

pub fn needsDraw(self: *App) bool {
    return self.draw.load(.acquire);
}

pub fn markDrawn(self: *App) void {
    self.draw.store(false, .release);
}

pub fn requestDraw(self: *App) void {
    self.draw.store(true, .release);
}

pub fn drawWindow(self: *App) !void {
    if (!self.needsDraw()) return;
    defer self.markDrawn();

    try self.window.draw();

    try self.renderer_thread.wakeup.notify();
}
