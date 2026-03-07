const std = @import("std");
const global = @import("global.zig");

const Settings = @import("settings/mod.zig");
const Io = @import("io/mod.zig");
const Monitor = @import("monitor/mod.zig");
const Project = @import("Project.zig");
const Snapshot = @import("worktree/Snapshot.zig");
const Buffer = @import("buffer/Buffer.zig");
const native = @import("native/mod.zig");

export fn initState(callback: ?global.Callback) void {
    global.state.init(callback);
}

export fn deinitState() void {
    global.state.deinit();
}

export fn drainMailbox() void {
    const cb = global.state.callback orelse return;
    var mailbox = global.state.mailbox;

    var it = mailbox.drain();
    defer it.deinit();

    while (it.next()) |ev| {
        const bytes: []const u8 = switch (ev) {
            .settings_update, .theme_update, .worktree_update => &.{},
        };
        const ptr: ?[*]const u8 = if (bytes.len > 0) bytes.ptr else null;
        cb(@intFromEnum(ev), ptr, bytes.len);
    }
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

pub const ExternSettings = extern struct {
    scheme: u64,
    light_theme_ptr: usize,
    light_theme_len: usize,
    dark_theme_ptr: usize,
    dark_theme_len: usize,
};

//BUG:
//i fucked up with this, i know
//i need to add a mutex for protecting the settings data (monitor thread and other threads)
//and i need to check how the ts side handle the data, it makes a copy?, it takes ownership of the ptr?,
//should i dupe the strings and then dealloc?
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
