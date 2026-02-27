const std = @import("std");
const global = @import("global.zig");
const Bus = @import("Bus.zig");

const Settings = @import("settings/mod.zig");
const Io = @import("io/mod.zig");
const Monitor = @import("monitor/mod.zig");

export fn initState(callback: ?Bus.JsCallback) void {
    global.state.init(callback);
}

export fn deinitState() void {
    global.state.deinit();
}

export fn drainEvents() void {
    global.state.bus.drain();
}
export fn createSettings() ?*Settings {
    return Settings.create(global.state.alloc) catch null;
}

export fn destroySettings(settings: *Settings) void {
    settings.destroy();
}

export fn loadSettings(settings: *Settings, path: [*]const u8, len: u64, monitor: *Monitor) void {
    settings.load(path[0..len], monitor) catch {};
}

pub const SettingsView = extern struct {
    scheme: u64,
    light_theme_ptr: usize,
    light_theme_len: usize,
    dark_theme_ptr: usize,
    dark_theme_len: usize,
};

export fn readSettings(settings: *Settings, buf: [*]u8) void {
    const view: *SettingsView = @ptrCast(@alignCast(buf));
    view.* = .{
        .scheme = @intFromEnum(settings.scheme),
        .light_theme_ptr = @intFromPtr(settings.light_theme.ptr),
        .light_theme_len = settings.light_theme.len,
        .dark_theme_ptr = @intFromPtr(settings.dark_theme.ptr),
        .dark_theme_len = settings.dark_theme.len,
    };
}

export fn createIo() ?*Io {
    return Io.create(global.state.alloc) catch null;
}

export fn destroyIo(io: *Io) void {
    io.destroy();
}

export fn createMonitor() ?*Monitor {
    return Monitor.create(global.state.alloc) catch null;
}

export fn destroyMonitor(monitor: *Monitor) void {
    monitor.destroy();
}

test {
    _ = @import("keymaps/mod.zig");
    _ = @import("monitor/mod.zig");
    _ = @import("worktree/mod.zig");
}
