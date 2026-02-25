const global = @import("global.zig");
const alloc = global.state.alloc;

const Settings = @import("settings/mod.zig");

export fn init_state() void {
    global.state.init();
}

export fn createSettings() !*Settings {
    return try Settings.create(alloc);
}

export fn destroySettings(settings: *Settings) void {
    settings.destroy();
}

export fn loadSettings(settings: *Settings, path: []const u8) !void {
    try settings.load(path);
}
