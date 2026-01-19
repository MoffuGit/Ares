const std = @import("std");
const vaxis = @import("vaxis");
const builtin = @import("builtin");
const posix = std.posix;

const SharedState = @import("SharedState.zig");

const RendererThread = @import("renderer/Thread.zig");
const Renderer = @import("renderer/mod.zig");

const WindowThread = @import("window/Thread.zig");
const Window = @import("window/mod.zig");

const Element = @import("window/Element.zig");

const log = std.log.scoped(.app);

const Allocator = std.mem.Allocator;

const ReadThread = @import("read/Thread.zig");

const App = @This();

alloc: Allocator,

shared_state: SharedState,
tty: vaxis.Tty,
buffer: [1024]u8 = undefined,

renderer: Renderer,
renderer_thread: RendererThread,
renderer_thr: std.Thread,

window: Window,
window_thread: WindowThread,

read_thread: ReadThread,
read_thr: std.Thread,

pub fn create(alloc: Allocator) !*App {
    var self = try alloc.create(App);

    var shared_state = try SharedState.init(alloc, .{ .cols = 0, .rows = 0, .x_pixel = 0, .y_pixel = 0 });
    errdefer shared_state.deinit(alloc);

    var renderer = try Renderer.init(alloc, &self.tty, &self.shared_state);
    errdefer renderer.deinit();

    var renderer_thread = try RendererThread.init(alloc, &self.renderer);
    errdefer renderer_thread.deinit();

    var window_thread = try WindowThread.init(alloc, &self.window);
    errdefer window_thread.deinit();

    var window = try Window.init(alloc, .{
        .render_wakeup = renderer_thread.wakeup,
        .render_mailbox = renderer_thread.mailbox,
        .shared_state = &self.shared_state,
        .window_mailbox = window_thread.mailbox,
        .window_wakeup = window_thread.wakeup,
        .reschedule_tick = window_thread.reschedule_tick,
    });
    errdefer window.deinit();

    var tty = try vaxis.Tty.init(&self.buffer);
    self.tty = tty;
    errdefer tty.deinit();

    const read_thread = ReadThread.init(alloc, &self.tty, window_thread.mailbox, window_thread.wakeup);

    self.* = .{
        .alloc = alloc,
        .shared_state = shared_state,
        .renderer = renderer,
        .renderer_thread = renderer_thread,
        .renderer_thr = undefined,
        .tty = tty,
        .window = window,
        .window_thread = window_thread,
        .read_thread = read_thread,
        .read_thr = undefined,
    };

    self.read_thr = try std.Thread.spawn(.{}, ReadThread.threadMain, .{&self.read_thread});
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
        self.read_thread.stop();
        self.read_thr.join();
    }

    self.renderer_thread.deinit();
    self.window_thread.deinit();

    self.window.deinit();
    self.renderer.deinit();
}

pub fn run(self: *App) !void {
    const winsize = try vaxis.Tty.getWinsize(self.tty.fd);

    _ = self.window_thread.mailbox.push(.{ .resize = winsize }, .instant);
    try self.window_thread.wakeup.notify();

    self.window_thread.threadMain();
}
