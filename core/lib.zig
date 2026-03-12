const std = @import("std");
const global = @import("global.zig");

const Settings = @import("settings/mod.zig");
const Io = @import("io/mod.zig");
const Monitor = @import("monitor/mod.zig");
const Project = @import("Project.zig");
const Snapshot = @import("worktree/Snapshot.zig");
const Buffer = @import("buffer/Buffer.zig");
const Appearance = @import("native/Appearance.zig");
const native = @import("native/mod.zig");

export fn initState(callback: ?global.Callback) void {
    global.state.init(callback) catch {};
}

export fn deinitState() void {
    global.state.deinit();
}

export fn drainMailbox() void {
    const cb = global.state.callback orelse return;
    var it = global.state.mailbox.drain();
    defer it.deinit();

    while (it.next()) |ev| {
        const bytes: []const u8 = switch (ev) {
            .settingsUpdate,
            .themeUpdate,
            .filetreeUpdate,
            => &.{},
        };
        const ptr: ?[*]const u8 = if (bytes.len > 0) bytes.ptr else null;
        cb(@intFromEnum(ev), ptr, bytes.len);
    }
}

export fn createAppearance() ?*Appearance {
    return Appearance.create(global.state.alloc) catch null;
}

export fn destroyAppearance(appe: *Appearance) void {
    appe.destroy();
}

export fn createSettings() ?*Settings {
    return Settings.create(global.state.alloc) catch null;
}

export fn destroySettings(settings: *Settings) void {
    settings.destroy();
}

export fn loadSettings(settings: *Settings, path: [*]const u8, len: u64, monitor: *Monitor, appe: ?*Appearance) void {
    settings.load(path[0..len], monitor, appe) catch |err| {
        std.log.err("error while loading the settings: {}", .{err});
    };
}

pub const ExternSettings = extern struct {
    scheme: u64,
    light_theme_ptr: usize,
    light_theme_len: usize,
    dark_theme_ptr: usize,
    dark_theme_len: usize,
};

export fn lockSettings(settings: *Settings) void {
    settings.mutex.lock();
}

export fn unlockSettings(settings: *Settings) void {
    settings.mutex.unlock();
}

export fn readSettings(settings: *Settings, @"extern": *ExternSettings) void {
    @"extern".* = .{
        .scheme = @intFromEnum(settings.scheme),
        .light_theme_ptr = @intFromPtr(settings.light_theme.ptr),
        .light_theme_len = settings.light_theme.len,
        .dark_theme_ptr = @intFromPtr(settings.dark_theme.ptr),
        .dark_theme_len = settings.dark_theme.len,
    };
}

pub const ExternTheme = extern struct {
    name: u64,
    len: u64,
    fg: [4]u8,
    bg: [4]u8,
    primaryBg: [4]u8,
    primaryFg: [4]u8,
    mutedBg: [4]u8,
    mutedFg: [4]u8,
    scrollThumb: [4]u8,
    scrollTrack: [4]u8,
    border: [4]u8,
    card: [4]u8,
    cardFg: [4]u8,
    popover: [4]u8,
    popoverFg: [4]u8,
    secondary: [4]u8,
    secondaryFg: [4]u8,
    accent: [4]u8,
    accentFg: [4]u8,
    destructive: [4]u8,
    destructiveFg: [4]u8,
    input: [4]u8,
    ring: [4]u8,
    chart1: [4]u8,
    chart2: [4]u8,
    chart3: [4]u8,
    chart4: [4]u8,
    chart5: [4]u8,
    sidebar: [4]u8,
    sidebarFg: [4]u8,
    sidebarPrimary: [4]u8,
    sidebarPrimaryFg: [4]u8,
    sidebarAccent: [4]u8,
    sidebarAccentFg: [4]u8,
    sidebarBorder: [4]u8,
    sidebarRing: [4]u8,
};

export fn readTheme(settings: *Settings, @"extern": *ExternTheme) void {
    const theme = settings.theme;
    @"extern".* = .{
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
        .card = theme.card,
        .cardFg = theme.cardFg,
        .popover = theme.popover,
        .popoverFg = theme.popoverFg,
        .secondary = theme.secondary,
        .secondaryFg = theme.secondaryFg,
        .accent = theme.accent,
        .accentFg = theme.accentFg,
        .destructive = theme.destructive,
        .destructiveFg = theme.destructiveFg,
        .input = theme.input,
        .ring = theme.ring,
        .chart1 = theme.chart1,
        .chart2 = theme.chart2,
        .chart3 = theme.chart3,
        .chart4 = theme.chart4,
        .chart5 = theme.chart5,
        .sidebar = theme.sidebar,
        .sidebarFg = theme.sidebarFg,
        .sidebarPrimary = theme.sidebarPrimary,
        .sidebarPrimaryFg = theme.sidebarPrimaryFg,
        .sidebarAccent = theme.sidebarAccent,
        .sidebarAccentFg = theme.sidebarAccentFg,
        .sidebarBorder = theme.sidebarBorder,
        .sidebarRing = theme.sidebarRing,
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

export fn createProject(monitor: *Monitor, io: *Io, path: [*]const u8, len: u64) ?*Project {
    return Project.create(global.state.alloc, monitor, io, path[0..len]) catch null;
}

export fn destroyProject(project: *Project) void {
    project.destroy(global.state.alloc);
}

pub const ExternWorktreeEntry = extern struct {
    id: u64,
    kind: u8,
    file_type: u8,
    depth: u16,
    path_ptr: usize,
    path_len: usize,
};

export fn getWorktreeEntryCount(project: *Project) usize {
    return project.worktree.count();
}

export fn readWorktreeEntries(project: *Project, out: [*]ExternWorktreeEntry, max_count: u64) u64 {
    project.worktree.snapshot.mutex.lock();
    defer project.worktree.snapshot.mutex.unlock();

    var it = project.worktree.snapshot.entries.iter();
    var i: u64 = 0;
    while (it.next()) |entry| {
        if (i >= max_count) break;
        const path = entry.key;
        const depth = countDepth(path);
        out[i] = .{
            .id = entry.value.id,
            .kind = @intFromEnum(entry.value.kind),
            .file_type = @intFromEnum(entry.value.file_type),
            .depth = depth,
            .path_ptr = @intFromPtr(path.ptr),
            .path_len = path.len,
        };
        i += 1;
    }
    return i;
}

fn countDepth(path: []const u8) u16 {
    var depth: u16 = 0;
    for (path) |c| {
        if (c == '/') depth += 1;
    }
    return depth;
}

export fn openBuffer(project: *Project, entry_id: u64) ?*Buffer {
    return project.openBuffer(entry_id);
}

test {
    _ = native;
    _ = @import("keymaps/mod.zig");
    _ = @import("monitor/mod.zig");
    _ = @import("worktree/mod.zig");
}
