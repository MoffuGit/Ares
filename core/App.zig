const global = &@import("global.zig").state;
const Settings = @import("settings/mod.zig");
const Appearance = @import("native/Appearance.zig");
const Monitor = @import("monitor/mod.zig");
const Io = @import("io/mod.zig");

pub const App = @This();

settings: *Settings,
appearance: *Appearance,
monitor: *Monitor,
io: *Io,

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

    app.* = .{
        .settings = settings,
        .appearance = appearance,
        .monitor = monitor,
        .io = io,
    };

    return app;
}

pub fn loadSettings(self: *App, path: []const u8) !void {
    try self.settings.load(path, self.monitor, self.appearance);
}

pub fn destroy(self: *App) void {
    self.settings.destroy();
    self.appearance.destroy();
    self.monitor.destroy();
    self.io.destroy();
    global.alloc.destroy(self);
}
