const std = @import("std");
const global = @import("global.zig");

const Project = @import("Project.zig");
const Snapshot = @import("worktree/Snapshot.zig");
const Appearance = @import("Appearance.zig");
const App = @import("App.zig");
const SurfacePkg = @import("Surface.zig");
const Editio = @import("Editio.zig");
const Termio = @import("Termio.zig");

const Editor = SurfacePkg.Surface(Editio);
const Terminal = SurfacePkg.Surface(Termio);

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
            => cb(@intFromEnum(ev), null, 0),
            .filetreeUpdate => {
                cb(@intFromEnum(ev), null, 0);
            },
            .surfaceUpdate => |surface| {
                cb(@intFromEnum(ev), @ptrCast(&surface), @sizeOf(global.ExternSurfaceState));
            },
            .bufferUpdate => |bs| {
                cb(@intFromEnum(ev), @ptrCast(&bs), @sizeOf(global.ExternEditorState));
            },
            .modeUpdate => |mode| {
                cb(@intFromEnum(ev), @ptrCast(&mode), @sizeOf(global.ExternModeUpdate));
            },
            .keymapMatch => |match| {
                defer global.state.alloc.free(match.sequence);
                defer global.state.alloc.free(match.action);

                const payload = global.ExternKeymapMatch{
                    .sequence_ptr = @intFromPtr(match.sequence.ptr),
                    .sequence_len = match.sequence.len,
                    .action_ptr = @intFromPtr(match.action.ptr),
                    .action_len = match.action.len,
                };
                cb(@intFromEnum(ev), @ptrCast(&payload), @sizeOf(global.ExternKeymapMatch));
            },
        }
    }
}

export fn createApp() ?*App {
    const app = App.create() catch |err| {
        std.log.debug("error when creating the app: {}", .{err});
        return null;
    };

    return app;
}

export fn destroyApp(app: *App) void {
    app.destroy();
}

export fn loadSettings(app: *App, path: [*]const u8, len: u64) void {
    app.loadSettings(path[0..len]) catch |err| {
        std.log.err("error while loading the settings: {}", .{err});
    };
}

export fn onKeyDown(app: *App, key_code: u32, modifiers: u32, is_repeat: bool) bool {
    return app.onKeyDown(key_code, modifiers, is_repeat);
}

pub const ExternSettings = extern struct {
    scheme: u64,
    system_scheme: u64,
    tabs_position: u64,
    light_theme_ptr: usize,
    light_theme_len: usize,
    dark_theme_ptr: usize,
    dark_theme_len: usize,
};

export fn lockSettings(app: *App) void {
    const settings = app.settings;

    settings.mutex.lock();
}

export fn unlockSettings(app: *App) void {
    const settings = app.settings;

    settings.mutex.unlock();
}

export fn readSettings(app: *App, @"extern": *ExternSettings) void {
    const settings = app.settings;

    @"extern".* = .{
        .scheme = @intFromEnum(settings.scheme),
        .system_scheme = @intFromEnum(settings.system_scheme),
        .tabs_position = @intFromEnum(settings.tabs_position),
        .light_theme_ptr = @intFromPtr(settings.light_theme.ptr),
        .light_theme_len = settings.light_theme.len,
        .dark_theme_ptr = @intFromPtr(settings.dark_theme.ptr),
        .dark_theme_len = settings.dark_theme.len,
    };
}

export fn setSystemScheme(app: *App, scheme: u8) void {
    const settings = app.settings;

    if (scheme >= @typeInfo(@import("settings/mod.zig").ColorScheme).@"enum".fields.len) return;
    settings.setSystemScheme(@enumFromInt(scheme));
}

export fn getThemeJsonLen(app: *App) u64 {
    return app.settings.theme_json.len;
}

export fn readThemeJson(app: *App, out_buf: [*]u8, buf_len: u64) void {
    const settings = app.settings;

    const len = @min(settings.theme_json.len, buf_len);
    @memcpy(out_buf[0..len], settings.theme_json[0..len]);
}

export fn createProject(app: *App, path: [*]const u8, len: u64) ?*Project {
    const project_path = path[0..len];
    return Project.create(global.state.alloc, app, project_path) catch |err| {
        std.log.err("createProject failed for path={s} err={}", .{ project_path, err });
        return null;
    };
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

export fn readFiletree(project: *Project, out: [*]ExternWorktreeEntry, max_count: u64) u64 {
    project.worktree.snapshot.mutex.lock();
    defer project.worktree.snapshot.mutex.unlock();

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

export fn getKeymapEntryCount(app: *App, scope: u8, mode: u8) u64 {
    const settings = app.settings;

    if (!settings.keymaps_initialized) return 0;
    if (scope >= @typeInfo(keymapspkg.Scope).@"enum".fields.len) return 0;
    if (mode >= @typeInfo(keymapspkg.Mode).@"enum".fields.len) return 0;

    const s: keymapspkg.Scope = @enumFromInt(scope);
    const m: keymapspkg.Mode = @enumFromInt(mode);
    return settings.keymaps.entries(s, m).len;
}

export fn readKeymapEntries(app: *App, scope: u8, mode: u8, out: [*]ExternKeymapEntry, max_count: u64) u64 {
    const settings = app.settings;

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

export fn createEditor(app: *App, project: *Project, layer_ptr: *anyopaque, width: u32, height: u32) ?*Editor {
    return Editor.create(global.state.alloc, &app.grid, layer_ptr, .{ .width = width, .height = height }, .{
        .project = project,
    }) catch null;
}

export fn createTerminal(app: *App, layer_ptr: *anyopaque, width: u32, height: u32) ?*Terminal {
    return Terminal.create(global.state.alloc, &app.grid, layer_ptr, .{ .width = width, .height = height }, .{}) catch null;
}

export fn destroyTerminal(terminal: *Terminal) void {
    terminal.destroy();
}

export fn resizeEditor(editor: *Editor, width: u32, height: u32) void {
    editor.sendIo(.{ .resize = .{ .height = height, .width = width } });
}

export fn destroyEditor(editor: *Editor) void {
    editor.destroy();
}

export fn setEditorVisibility(editor: *Editor, visible: bool) void {
    editor.setVisibility(visible) catch {};
}

export fn selectEditorEntry(editor: *Editor, id: u64) void {
    editor.sendIo(.{ .select_entry = id });
}

export fn editorScrollTo(editor: *Editor, row: u64) void {
    editor.sendIo(.{ .scroll = row });
}

pub const ExternSurfaceState = global.ExternSurfaceState;
pub const ExternEditorState = global.ExternEditorState;

export fn readEditorSurfaceState(editor: *Editor, out: *ExternSurfaceState) void {
    editor.state(out);
}

export fn readTerminalSurfaceState(terminal: *Terminal, out: *ExternSurfaceState) void {
    terminal.state(out);
}

export fn readEditorState(editor: *Editor, out: *ExternEditorState) bool {
    return editor.io.readEditorState(out);
}

test {
    _ = @import("keymaps/mod.zig");
    _ = @import("monitor/mod.zig");
    _ = @import("worktree/mod.zig");
}
