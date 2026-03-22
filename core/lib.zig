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
const GpuContext = native.gpu.GpuContext;

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
        switch (ev) {
            .settingsUpdate,
            .themeUpdate,
            .filetreeUpdate,
            => cb(@intFromEnum(ev), null, 0),
            .bufferUpdate => |entry_id| {
                const bytes = std.mem.asBytes(&entry_id);
                cb(@intFromEnum(ev), bytes.ptr, bytes.len);
            },
        }
    }
}

export fn createAppearance() ?*Appearance {
    return Appearance.create(global.state.alloc) catch null;
}

export fn destroyAppearance(appe: *Appearance) void {
    appe.destroy();
}

export fn setWindowTrafficLightsPosition(window_ptr: *anyopaque, x: f64, y_from_top: f64) bool {
    return Appearance.setWindowTrafficLightsPosition(window_ptr, x, y_from_top);
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
    system_scheme: u64,
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
        .system_scheme = @intFromEnum(settings.system_scheme),
        .light_theme_ptr = @intFromPtr(settings.light_theme.ptr),
        .light_theme_len = settings.light_theme.len,
        .dark_theme_ptr = @intFromPtr(settings.dark_theme.ptr),
        .dark_theme_len = settings.dark_theme.len,
    };
}

export fn setSystemScheme(settings: *Settings, scheme: u8) void {
    if (scheme >= @typeInfo(@import("settings/mod.zig").ColorScheme).@"enum".fields.len) return;
    settings.setSystemScheme(@enumFromInt(scheme));
    global.state.emit(.themeUpdate, .instant);
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
    is_expanded: bool,
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
        const is_expanded = project.filetree.expanded_entries.contains(entry.id);
        out[i] = .{
            .id = entry.id,
            .kind = @intFromEnum(entry.kind),
            .is_expanded = is_expanded,
            .depth = depth,
            .path_ptr = @intFromPtr(path.ptr),
            .path_len = path.len,
            .file_type_ptr = @intFromPtr(entry.file_type.ptr),
            .file_type_len = entry.file_type.len,
        };
    }
    return i;
}

export fn expandEntry(project: *Project, id: u64) void {
    project.filetree.expandEntry(id);
}

fn countDepth(path: []const u8) u16 {
    var depth: u16 = 0;
    for (path) |c| {
        if (c == '/') depth += 1;
    }
    return depth;
}

const keymapspkg = @import("keymaps/mod.zig");

pub const ExternKeymapEntry = extern struct {
    sequence_ptr: usize,
    sequence_len: usize,
    action_ptr: usize,
    action_len: usize,
};

export fn getKeymapEntryCount(settings: *Settings, scope: u8, mode: u8) u64 {
    if (!settings.keymaps_initialized) return 0;
    if (scope >= @typeInfo(keymapspkg.Scope).@"enum".fields.len) return 0;
    if (mode >= @typeInfo(keymapspkg.Mode).@"enum".fields.len) return 0;

    const s: keymapspkg.Scope = @enumFromInt(scope);
    const m: keymapspkg.Mode = @enumFromInt(mode);
    return settings.keymaps.entries(s, m).len;
}

export fn readKeymapEntries(settings: *Settings, scope: u8, mode: u8, out: [*]ExternKeymapEntry, max_count: u64) u64 {
    if (!settings.keymaps_initialized) return 0;
    if (scope >= @typeInfo(keymapspkg.Scope).@"enum".fields.len) return 0;
    if (mode >= @typeInfo(keymapspkg.Mode).@"enum".fields.len) return 0;

    const s: keymapspkg.Scope = @enumFromInt(scope);
    const m: keymapspkg.Mode = @enumFromInt(mode);
    const entries = settings.keymaps.entries(s, m);

    const count = @min(entries.len, max_count);
    for (0..count) |i| {
        const entry = entries[i];
        out[i] = .{
            .sequence_ptr = @intFromPtr(entry.sequence.ptr),
            .sequence_len = entry.sequence.len,
            .action_ptr = @intFromPtr(entry.action.ptr),
            .action_len = entry.action.len,
        };
    }
    return count;
}

const KeyStroke = @import("keymaps/KeyStroke.zig").KeyStroke;
const KeyStrokeContext = @import("keymaps/KeyStroke.zig").KeyStrokeContext;
const triepkg = @import("datastruct");
const TrieNode = triepkg.NodeType(KeyStroke, u8, KeyStrokeContext);

export fn getTrieRoot(settings: *Settings, mode: u8) ?*TrieNode {
    if (!settings.keymaps_initialized) return null;
    if (mode >= @typeInfo(keymapspkg.Mode).@"enum".fields.len) return null;

    const m: keymapspkg.Mode = @enumFromInt(mode);
    return settings.keymaps.trie(m).root;
}

export fn trieStep(node: *TrieNode, codepoint: u32, mods: u8) ?*TrieNode {
    const ks = KeyStroke{ .codepoint = @truncate(codepoint), .mods = @bitCast(mods) };
    return node.childrens.get(ks);
}

export fn trieNodeIsTerminal(node: *TrieNode) bool {
    return node.values.items.len > 0;
}

export fn trieNodeHasChildren(node: *TrieNode) bool {
    return node.childrens.count() > 0;
}

pub const ExternBuffer = extern struct {
    state: u8,
    bytes_ptr: usize,
    bytes_len: usize,
};

export fn openBuffer(project: *Project, entry_id: u64) ?*Buffer {
    return project.openBuffer(entry_id);
}

export fn closeBuffer(project: *Project, entry_id: u64) void {
    project.buffer_store.close(entry_id);
}

export fn readBuffer(buf: *Buffer, out: *ExternBuffer) void {
    const bytes = buf.bytes();
    out.* = .{
        .state = @intFromEnum(buf.state),
        .bytes_ptr = if (bytes) |b| @intFromPtr(b.ptr) else 0,
        .bytes_len = if (bytes) |b| b.len else 0,
    };
}

export fn gpuInit(metal_layer_ptr: *anyopaque) ?*GpuContext {
    return GpuContext.init(global.state.alloc, metal_layer_ptr) catch null;
}

export fn gpuStartRenderLoop(ctx: *GpuContext) void {
    ctx.startRenderLoop() catch {};
}

export fn gpuResize(ctx: *GpuContext, width: u32, height: u32) void {
    ctx.resize(width, height);
}

export fn gpuDestroy(ctx: *GpuContext) void {
    ctx.destroy();
}

test {
    _ = native;
    _ = @import("keymaps/mod.zig");
    _ = @import("monitor/mod.zig");
    _ = @import("worktree/mod.zig");
}
