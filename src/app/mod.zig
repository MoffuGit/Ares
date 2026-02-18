const std = @import("std");
const vaxis = @import("vaxis");
const log = std.log.scoped(.app);
const messagepkg = @import("message.zig");
const EventListeners = @import("events.zig").EventListeners;
const UpdatedEntriesSet = @import("../worktree/scanner/mod.zig").UpdatedEntriesSet;

pub const EventType = enum {
    scheme,
    worktreeUpdatedEntries,
    bufferUpdated,
};

pub const EventData = union(EventType) {
    scheme: vaxis.Color.Scheme,
    worktreeUpdatedEntries: *UpdatedEntriesSet,
    bufferUpdated: u64,
};

pub const AppEventListeners = EventListeners(EventType, EventData);

const Allocator = std.mem.Allocator;

const SharedContext = @import("SharedContext.zig");
const Screen = @import("Screen.zig");

const Loop = @import("Loop.zig");

const TtyThread = @import("TtyThread.zig");

const Renderer = @import("renderer/mod.zig");
const RendererThread = @import("renderer/Thread.zig");

const Window = @import("window/mod.zig");
const Element = Window.Element;

pub const Message = messagepkg.Message;

pub const Context = struct {
    app: *App,
    userdata: ?*anyopaque,

    pub fn requestDraw(self: *Context) void {
        self.app.requestDraw();
    }

    pub fn startAnimation(self: *Context, animation: *Element.Animation.BaseAnimation) void {
        animation.context = self;
        _ = self.app.loop.mailbox.push(.{ .window = .{ .animation = .{ .start = animation } } }, .instant);
        self.app.loop.wakeup.notify() catch {};
    }

    pub fn pauseAnimation(self: *Context, id: u64) void {
        _ = self.app.loop.mailbox.push(.{ .window = .{ .animation = .{ .pause = id } } }, .instant);
        self.app.loop.wakeup.notify() catch {};
    }

    pub fn resumeAnimation(self: *Context, id: u64) void {
        _ = self.app.loop.mailbox.push(.{ .window = .{ .animation = .{ ._resume = id } } }, .instant);
        self.app.loop.wakeup.notify() catch {};
    }

    pub fn cancelAnimation(self: *Context, id: u64) void {
        _ = self.app.loop.mailbox.push(.{ .window = .{ .animation = .{ .cancel = id } } }, .instant);
        self.app.loop.wakeup.notify() catch {};
    }

    pub fn stop(self: *Context) !void {
        try self.app.loop.stop.notify();
    }

    pub fn subscribe(
        self: *Context,
        event: EventType,
        comptime Userdata: type,
        userdata: *Userdata,
        cb: *const fn (userdata: *Userdata, data: EventData) void,
    ) !void {
        try self.app.subscribe(event, Userdata, userdata, cb);
    }
};

pub const Options = struct {
    root: Element.Options = .{},
    userdata: ?*anyopaque = null,
};

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

window: Window,
draw: std.atomic.Value(bool) = .init(true),
context: Context,

scheme: vaxis.Color.Scheme = .dark,

subs: AppEventListeners = .{},

pub fn create(alloc: Allocator, opts: Options) !*App {
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
        .{ .context = &app.context, .root = opts.root },
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
        .context = .{
            .app = app,
            .userdata = opts.userdata,
        },
        .screen = screen,
        .window = window,
        .tty_thread = tty_thread,
        .renderer = renderer,
        .renderer_thread = renderer_thread,
        .renderer_thr = undefined,
        .tty_thr = undefined,
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

    self.loop.deinit();

    self.window.deinit();
    self.renderer.deinit();

    self.subs.deinit(self.alloc);

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

pub fn root(self: *App) *Window.Element {
    return self.window.root;
}

pub fn run(self: *App) !void {
    const winsize = try vaxis.Tty.getWinsize(self.shared_context.tty.fd);

    self.window.resize(winsize);
    self.loop.threadMain();
}

pub fn drawWindow(self: *App) !void {
    if (!self.needsDraw()) return;
    defer self.markDrawn();

    try self.window.draw();

    try self.renderer_thread.wakeup.notify();
}

pub fn handleMessage(self: *App, msg: Message) !void {
    switch (msg) {
        .scheme => |scheme| {
            self.scheme = scheme;
            self.notifySubs(.{ .scheme = scheme });
        },
        .worktreeUpdatedEntries => |entries| {
            self.notifySubs(.{ .worktreeUpdatedEntries = entries });
            entries.destroy();
        },
        .bufferUpdated => |entry_id| {
            self.notifySubs(.{ .bufferUpdated = entry_id });
        },
    }
}

pub fn notifySubs(self: *App, data: EventData) void {
    self.subs.notify(data);
}

pub fn subscribe(
    self: *App,
    event: EventType,
    comptime Userdata: type,
    userdata: *Userdata,
    cb: *const fn (userdata: *Userdata, data: EventData) void,
) !void {
    try self.subs.addSubscription(self.alloc, event, Userdata, userdata, cb);
}
