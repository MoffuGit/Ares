const std = @import("std");
const global = @import("global.zig");
const sizepkg = @import("size.zig");
const inputpkg = @import("input.zig");
const ghostty_vt = @import("ghostty-vt");

const Project = @import("Project.zig");
const Snapshot = @import("worktree/Snapshot.zig");
const Appearance = @import("Appearance.zig");
const App = @import("App.zig");
const SurfacePkg = @import("Surface.zig");
const Editio = @import("Editio.zig");
const Termio = @import("Termio.zig");
const Allocator = std.mem.Allocator;

const Editor = @import("Editor.zig");
const Terminal = @import("Terminal.zig");
const Modifiers = @import("keymaps/KeyStroke.zig").Modifiers;

const EditorSurface = SurfacePkg.Surface(Editio, Editor);
const TerminalSurface = SurfacePkg.Surface(Termio, Terminal);

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
            .editorUpdate => |bs| {
                cb(@intFromEnum(ev), @ptrCast(&bs), @sizeOf(global.ExternEditorState));
            },
            .keymapMatch => |match| {
                defer global.state.alloc.free(match.sequence);

                const payload = global.ExternKeymapMatch{
                    .sequence_ptr = @intFromPtr(match.sequence.ptr),
                    .sequence_len = match.sequence.len,
                };
                cb(@intFromEnum(ev), @ptrCast(&payload), @sizeOf(global.ExternKeymapMatch));
            },
        }
    }
}

export fn createApp(window: *anyopaque) ?*App {
    const app = App.create(window) catch |err| {
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

    settings.rwlock.lockShared();
}

export fn unlockSettings(app: *App) void {
    const settings = app.settings;

    settings.rwlock.unlockShared();
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

export fn setMode(app: *App, mode: u8) void {
    if (mode >= @typeInfo(@import("keymaps/mod.zig").Mode).@"enum".fields.len) return;
    app.setMode(@enumFromInt(mode));
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
    project.worktree.snapshot.rwlock.lockShared();
    defer project.worktree.snapshot.rwlock.unlockShared();

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

export fn createEditor(app: *App, project: *Project, surface_id: u64, layer_ptr: *anyopaque, width: u32, height: u32) ?*EditorSurface {
    const state = Editor.init(
        global.state.alloc,
        surface_id,
        project,
        app.settings,
        .{ .cell = app.grid.cellSize(), .screen = .{ .height = height, .width = width } },
    );

    return EditorSurface.create(
        global.state.alloc,
        surface_id,
        &app.grid,
        layer_ptr,
        .{ .width = width, .height = height },
        state,
        app.settings,
    ) catch null;
}

export fn createTerminal(app: *App, surface_id: u64, layer_ptr: *anyopaque, width: u32, height: u32) ?*TerminalSurface {
    const screen_size: sizepkg.ScreenSize = .{ .width = width, .height = height };

    const grid_size = (sizepkg.Size{ .screen = screen_size, .cell = app.grid.cellSize() }).grid();

    const state = Terminal.init(global.state.alloc, .{
        .cols = grid_size.columns,
        .rows = grid_size.rows,
        .max_scrollback = 1000,
    }) catch return null;

    return TerminalSurface.create(
        global.state.alloc,
        surface_id,
        &app.grid,
        layer_ptr,
        screen_size,
        state,
        app.settings,
    ) catch null;
}

export fn destroyTerminal(terminal: *TerminalSurface) void {
    terminal.destroy();
}

export fn resizeEditor(editor: *EditorSurface, width: u32, height: u32) void {
    editor.sendIo(.{ .resize = .{ .screen = .{ .height = height, .width = width }, .cell = editor.grid.cellSize() } });
}

export fn destroyEditor(editor: *EditorSurface) void {
    editor.destroy();
}

export fn setEditorVisibility(editor: *EditorSurface, visible: bool) void {
    editor.setVisibility(visible) catch {};
}

export fn selectEditorEntry(editor: *EditorSurface, id: u64) void {
    editor.sendIo(.{ .select_entry = id });
}

export fn editorScrollTo(editor: *EditorSurface, row: u64) void {
    editor.sendIo(.{ .scroll = row });
}

export fn editorSetCursorPosition(editor: *EditorSurface, row: u64, col: u64) void {
    editor.sendIo(.{ .set_cursor_position = .{ .row = row, .col = col } });
}

export fn editorSurfaceMouseButton(surface: *EditorSurface, button: u8, action: u8, x: f64, y: f64, mods: u8) void {
    if (button >= @typeInfo(inputpkg.MouseButton).@"enum".fields.len) return;
    if (action >= @typeInfo(inputpkg.MouseAction).@"enum".fields.len) return;

    const event = inputpkg.MouseButtonEvent{
        .button = @enumFromInt(button),
        .action = @enumFromInt(action),
        .x = x,
        .y = y,
        .mods = @bitCast(mods),
    };

    surface.sendIo(.{ .mouse_button = event });
}

export fn editorSurfaceMouseMove(surface: *EditorSurface, x: f64, y: f64, mods: u8) void {
    const event = inputpkg.MouseMoveEvent{
        .x = x,
        .y = y,
        .mods = @bitCast(mods),
    };

    surface.sendIo(.{ .mouse_move = event });
}

export fn editorSurfaceKeyEvent(
    surface: *EditorSurface,
    key_ptr: [*]const u8,
    key_len: u64,
    mods: u8,
    repeat: bool,
) void {
    const key = key_ptr[0..key_len];
    const event = inputpkg.parseDomKeyEvent(key, @bitCast(mods), repeat) orelse return;

    surface.sendIo(.{ .key = event });
}

pub const ExternSurfaceState = global.ExternSurfaceState;
pub const ExternEditorState = global.ExternEditorState;

export fn readEditorSurfaceState(editor: *EditorSurface, out: *ExternSurfaceState) void {
    editor.surfaceState(out);
}

export fn readTerminalSurfaceState(terminal: *TerminalSurface, out: *ExternSurfaceState) void {
    terminal.surfaceState(out);
}

export fn readEditorState(editor: *EditorSurface, out: *ExternEditorState) bool {
    return editor.state.readEditorState(out);
}

test {
    _ = @import("keymaps/mod.zig");
    _ = @import("monitor/mod.zig");
    _ = @import("worktree/mod.zig");
}
