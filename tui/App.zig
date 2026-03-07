const std = @import("std");
const vaxis = @import("vaxis");
const log = std.log.scoped(.app);
const datastruct = @import("datastruct");
const global = @import("global.zig");

const Allocator = std.mem.Allocator;

const SharedContext = @import("SharedContext.zig");
const Screen = @import("Screen.zig");

const TtyThread = @import("TtyThread.zig");

const Renderer = @import("renderer/mod.zig");
const RendererThread = @import("renderer/Thread.zig");

const Window = @import("window/mod.zig");

const BlockingQueue = datastruct.BlockingQueue;

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

const App = @This();

alloc: Allocator,

shared_context: SharedContext,
tty_thread: TtyThread,
tty_thr: std.Thread,

screen: Screen,
renderer: Renderer,
renderer_thread: RendererThread,
renderer_thr: std.Thread,

window: Window,
draw: std.atomic.Value(bool) = .init(true),
mailbox: *Mailbox,

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

    var mailbox = try Mailbox.create(alloc);
    errdefer mailbox.destroy(alloc);

    var window = try Window.init(
        alloc,
        &app.screen,
    );
    errdefer window.deinit();

    var tty_thread = TtyThread.init(alloc, &app.shared_context, mailbox);
    _ = &tty_thread;

    var renderer = try Renderer.init(alloc, &app.shared_context, &app.screen);
    errdefer renderer.deinit();

    var renderer_thread = try RendererThread.init(alloc, &app.renderer);
    errdefer renderer_thread.deinit();

    app.* = .{
        .alloc = alloc,
        .shared_context = shared_context,
        .mailbox = mailbox,
        .screen = screen,
        .window = window,
        .tty_thread = tty_thread,
        .tty_thr = undefined,
        .renderer = renderer,
        .renderer_thread = renderer_thread,
        .renderer_thr = undefined,
    };

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

    self.renderer_thread.deinit();

    self.mailbox.destroy(self.alloc);

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

pub fn drainMailbox(self: *App) void {
    var state = global.state;
    var it = self.mailbox.drain();
    defer it.deinit();

    while (it.next()) |evt| {
        switch (evt) {
            .scheme => |scheme| {
                state.notify(.{ .scheme = @intFromEnum(scheme) }, 0);
            },
            .resize => |size| {
                self.window.resize(size);
                state.notify(.{ .resize = .{ .cols = size.cols, .rows = size.rows } }, 0);
            },
            .key_press => |key| {
                state.notify(.{ .key_down = global.KeyEvent.fromVaxis(key) }, self.window.target());
            },
            .key_release => |key| {
                state.notify(.{ .key_up = global.KeyEvent.fromVaxis(key) }, self.window.target());
            },
            .focus => {
                state.notify(.focus, 0);
            },
            .blur => {
                state.notify(.blur, 0);
            },
            .mouse => |mouse| {
                self.window.resolveMouseEvent(mouse);
            },
        }
    }
}
