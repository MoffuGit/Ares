const global = &@import("global.zig").state;
const Settings = @import("settings/mod.zig");
const Appearance = @import("Appearance.zig");
const Monitor = @import("monitor/mod.zig");
const Io = @import("io/mod.zig");
const Grid = @import("font/Grid.zig");
const KeymapRuntime = @import("keymaps/runtime.zig").Runtime;

pub const App = @This();

settings: *Settings,
appearance: *Appearance,
monitor: *Monitor,
io: *Io,
grid: Grid,
keymaps: KeymapRuntime,

pub fn create() !*App {
    const app = try global.alloc.create(App);
    errdefer global.alloc.destroy(app);

    const appearance = try Appearance.create(global.alloc);
    errdefer global.alloc.destroy(appearance);

    const settings = try Settings.create(global.alloc);
    errdefer global.alloc.destroy(settings);

    const monitor = try Monitor.create(global.alloc);
    errdefer global.alloc.destroy(monitor);

    const io = try Io.create(global.alloc);
    errdefer global.alloc.destroy(io);

    var grid = try Grid.init(global.alloc, .{ .size = .{
        .points = 10,
    } });
    errdefer grid.deinit(global.alloc);

    app.* = .{
        .grid = grid,
        .settings = settings,
        .appearance = appearance,
        .monitor = monitor,
        .io = io,
        .keymaps = KeymapRuntime.init(global.alloc),
    };

    return app;
}

pub fn loadSettings(self: *App, path: []const u8) !void {
    try self.settings.load(path, self.monitor, self.appearance);
}

pub fn onKeyDown(self: *App, key_code: u32, modifiers: u32, is_repeat: bool) bool {
    self.settings.mutex.lock();
    defer self.settings.mutex.unlock();

    return self.keymaps.handleKeyDown(self.settings, key_code, modifiers, is_repeat);
}

pub fn destroy(self: *App) void {
    self.keymaps.deinit();
    self.grid.deinit(global.alloc);
    self.settings.destroy();
    self.appearance.destroy();
    self.monitor.destroy();
    self.io.destroy();
    global.alloc.destroy(self);
}
