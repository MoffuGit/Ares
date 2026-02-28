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

pub const PackedSettings = extern struct {
    scheme: u64,
    light_theme_ptr: usize,
    light_theme_len: usize,
    dark_theme_ptr: usize,
    dark_theme_len: usize,
};

export fn readSettings(settings: *Settings, buf: [*]u8) void {
    const pack: *PackedSettings = @ptrCast(@alignCast(buf));
    pack.* = .{
        .scheme = @intFromEnum(settings.scheme),
        .light_theme_ptr = @intFromPtr(settings.light_theme.ptr),
        .light_theme_len = settings.light_theme.len,
        .dark_theme_ptr = @intFromPtr(settings.dark_theme.ptr),
        .dark_theme_len = settings.dark_theme.len,
    };
}

pub const PackedTheme = extern struct {
    name: u64,
    len: u64,
    bg: [4]u8,
    fg: [4]u8,
    primaryBg: [4]u8,
    primaryFg: [4]u8,
    mutedBg: [4]u8,
    mutedFg: [4]u8,
    scrollThumb: [4]u8,
    scrollTrack: [4]u8,
    border: [4]u8,
};

export fn readTheme(settings: *Settings, buf: [*]u8) void {
    const pack: *PackedTheme = @ptrCast(@alignCast(buf));
    const theme = settings.theme;
    pack.* = .{
        .name = @intFromPtr(theme.name.ptr),
        .len = theme.name.len,
        .bg = theme.bg,
        .fg = theme.fg,
        .border = theme.border,
        .mutedBg = theme.mutedBg,
        .mutedFg = theme.mutedFg,
        .primaryBg = theme.primaryBg,
        .primaryFg = theme.primaryFg,
        .scrollThumb = theme.scrollThumb,
        .scrollTrack = theme.scrollTrack,
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
