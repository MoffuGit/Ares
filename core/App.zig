const globalpkg = @import("global.zig");
const std = @import("std");
const global = &globalpkg.state;
const Settings = @import("settings/mod.zig");
const Appearance = @import("Appearance.zig");
const Monitor = @import("monitor/mod.zig");
const Io = @import("io/mod.zig");
const Grid = @import("font/Grid.zig");
const KeymapRuntime = @import("keymaps/runtime.zig").Runtime;
const xev = globalpkg.xev;
const objc = @import("objc");

pub const App = @This();

settings: *Settings,
appearance: *Appearance,
monitor: *Monitor,
io: *Io,
thread_pool: *xev.ThreadPool,
grid: Grid,
keymaps: KeymapRuntime,
window: objc.Object,

pub fn create(window: *anyopaque) !*App {
    const app = try global.alloc.create(App);
    errdefer global.alloc.destroy(app);

    const appearance = try Appearance.create(global.alloc);
    errdefer global.alloc.destroy(appearance);

    const settings = try Settings.create(global.alloc);
    errdefer global.alloc.destroy(settings);

    const monitor = try Monitor.create(global.alloc);
    errdefer global.alloc.destroy(monitor);

    const thread_pool = try global.alloc.create(xev.ThreadPool);
    errdefer global.alloc.destroy(thread_pool);
    thread_pool.* = xev.ThreadPool.init(.{});
    errdefer {
        thread_pool.shutdown();
        thread_pool.deinit();
    }

    const io = try Io.create(global.alloc, thread_pool);
    errdefer global.alloc.destroy(io);

    var grid = try Grid.init(global.alloc, .{ .size = .{
        .points = 12,
    } });
    errdefer grid.deinit(global.alloc);

    app.* = .{
        .grid = grid,
        .window = objc.Object.fromId(window),
        .settings = settings,
        .appearance = appearance,
        .monitor = monitor,
        .io = io,
        .thread_pool = thread_pool,
        .keymaps = KeymapRuntime.init(global.alloc),
    };

    setKeyHandlerCallback(app.window, keyHandlerCallback, @ptrCast(app));

    return app;
}

pub const WindowCallback = ?*const fn (?*anyopaque, u32, u32, bool, bool) callconv(.c) bool;

fn setKeyHandlerCallback(window: objc.Object, cb: WindowCallback, ctx: ?*anyopaque) void {
    window.msgSend(void, objc.sel("setKeyHandlerCallback:context:"), .{ cb, ctx });
}

fn keyHandlerCallback(ctx: ?*anyopaque, keycode: u32, mods: u32, is_down: bool, is_repeated: bool) callconv(.c) bool {
    if (ctx == null) return false;
    const self: *App = @ptrCast(@alignCast(ctx));
    if (is_down) {
        return self.onKeyDown(keycode, mods, is_repeated);
    }

    return false;
}

pub fn loadSettings(self: *App, path: []const u8) !void {
    try self.settings.load(path, self.monitor, self.appearance);
}

pub fn onKeyDown(self: *App, key_code: u32, modifiers: u32, is_repeat: bool) bool {
    self.settings.rwlock.lockShared();
    defer self.settings.rwlock.unlockShared();

    return self.keymaps.handleKeyDown(self.settings, key_code, modifiers, is_repeat);
}

pub fn destroy(self: *App) void {
    self.keymaps.deinit();
    self.grid.deinit(global.alloc);
    self.settings.destroy();
    self.appearance.destroy();
    self.monitor.destroy();
    self.io.destroy();
    self.thread_pool.shutdown();
    self.thread_pool.deinit();
    global.alloc.destroy(self.thread_pool);
    global.alloc.destroy(self);
}
