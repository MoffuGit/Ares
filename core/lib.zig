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

export fn getThemeJsonLen(settings: *Settings) u64 {
    return settings.theme_json.len;
}

export fn readThemeJson(settings: *Settings, out_buf: [*]u8, buf_len: u64) void {
    const len = @min(settings.theme_json.len, buf_len);
    @memcpy(out_buf[0..len], settings.theme_json[0..len]);
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
    depth: u16,
    path_ptr: usize,
    path_len: usize,
    file_type_ptr: usize,
    file_type_len: usize,
};

export fn getFiletreeCount(project: *Project) usize {
    return project.filetree.visible_entries.items.len;
}

export fn lockWorktree(project: *Project) void {
    project.worktree.snapshot.mutex.lock();
}

export fn unlockWorktree(project: *Project) void {
    project.worktree.snapshot.mutex.unlock();
}

export fn readFiletree(project: *Project, out: [*]ExternWorktreeEntry, max_count: u64) u64 {
    project.filetree.mutex.lock();
    defer project.filetree.mutex.unlock();

    const ids = project.filetree.visible_entries.items;
    var i: u64 = 0;
    while (i < max_count) : (i += 1) {
        const id = ids[i];
        const path = project.worktree.snapshot.getPathById(id) orelse continue;
        const entry = project.worktree.snapshot.entries.get(path) catch continue;

        const depth = countDepth(path);
        out[i] = .{
            .id = entry.id,
            .kind = @intFromEnum(entry.kind),
            .depth = depth,
            .path_ptr = @intFromPtr(path.ptr),
            .path_len = path.len,
            .file_type_ptr = @intFromPtr(entry.file_type.ptr),
            .file_type_len = entry.file_type.len,
        };
    }
    return i;
}

export fn selectEntry(project: *Project, id: u64) void {
    project.filetree.selectEntry(id);
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
