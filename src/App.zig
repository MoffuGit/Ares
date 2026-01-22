const std = @import("std");
const vaxis = @import("vaxis");

const Screen = @import("Screen.zig");

const RendererThread = @import("renderer/Thread.zig");
const Renderer = @import("renderer/mod.zig");

const Loop = @import("Loop.zig");

const EventsThread = @import("events/Thread.zig");

const Window = @import("Window.zig");
const Element = @import("element/mod.zig").Element;

const TimeManager = @import("TimeManager.zig");
const AppContext = @import("AppContext.zig");

const log = std.log.scoped(.app);

const Allocator = std.mem.Allocator;

const App = @This();

var tty_buffer: [1024]u8 = undefined;

const Options = struct {
    userdata: ?*anyopaque = null,
    root_opts: Element.Options = .{},
};

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

window: Window,
app_context: AppContext,
userdata: ?*anyopaque,

pub fn create(alloc: Allocator, opts: Options) !*App {
    var self = try alloc.create(App);

    var screen = try Screen.init(alloc, .{
        .cols = 0,
        .rows = 0,
        .x_pixel = 0,
        .y_pixel = 0,
    });
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

    const events_thread = EventsThread.init(
        alloc,
        &self.tty,
        loop.mailbox,
        loop.wakeup,
    );

    var time = TimeManager.init(alloc);
    errdefer time.deinit();

    var window = try Window.init(alloc, &self.screen, .{
        .app_context = &self.app_context,
        .root_opts = opts.root_opts,
    });
    errdefer window.deinit();

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
        .window = window,
        .userdata = opts.userdata,
        .app_context = undefined,
    };

    self.app_context = .{
        .mailbox = self.loop.mailbox,
        .wakeup = self.loop.wakeup,
        .needs_draw = &self.window.needs_draw,
        .stop = self.loop.stop,
        .userdata = self.userdata,
        .window = &self.window,
    };

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
        const writer = self.tty.writer();
        writer.writeAll(vaxis.ctlseqs.device_status_report) catch {};
        writer.flush() catch {};
        self.events_thr.join();
    }

    self.renderer_thread.deinit();

    self.window.deinit();
    self.time.deinit();

    self.loop.deinit();
    self.tty.deinit();

    self.renderer.deinit();
    self.screen.deinit(self.alloc);
    self.alloc.destroy(self);
}

pub fn run(self: *App) !void {
    const winsize = try vaxis.Tty.getWinsize(self.tty.fd);

    self.window.resize(winsize);

    try self.loop.wakeup.notify();

    self.loop.run();
}

pub fn draw(self: *App) !void {
    if (!self.window.needsDraw()) return;
    self.window.markDrawn();

    try self.window.draw();

    try self.renderer_thread.wakeup.notify();
}

pub fn resize(self: *App, size: vaxis.Winsize) void {
    self.window.resize(size);
}
