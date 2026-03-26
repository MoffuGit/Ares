const std = @import("std");
const global = @import("global.zig");

const Project = @import("Project.zig");
const Snapshot = @import("worktree/Snapshot.zig");
const Appearance = @import("Appearance.zig");
const App = @import("App.zig");
const Surface = @import("Surface.zig");
const Editor = @import("Editor.zig");

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
            .bufferUpdate,
            => cb(@intFromEnum(ev), null, 0),
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

//HACK:
//This works but every time you resize the window, the buttons take their original position
//this result on blinking and jumping buttons, this pull maybe add a fix to the native electrobun
//api: https://github.com/blackboardsh/electrobun/pull/294,
//i will try the fix by myself and if i see that don't works i will try to fix it myself
export fn setWindowTrafficLightsPosition(window_ptr: *anyopaque, x: f64, y_from_top: f64) bool {
    return Appearance.setWindowTrafficLightsPosition(window_ptr, x, y_from_top);
}

export fn loadSettings(app: *App, path: [*]const u8, len: u64) void {
    app.loadSettings(path[0..len]) catch |err| {
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
    global.state.emit(.themeUpdate, .instant);
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
    return Project.create(global.state.alloc, app, path[0..len]) catch null;
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

const KeyStroke = @import("keymaps/KeyStroke.zig").KeyStroke;
const KeyStrokeContext = @import("keymaps/KeyStroke.zig").KeyStrokeContext;
const triepkg = @import("datastruct");
const TrieNode = triepkg.NodeType(KeyStroke, u8, KeyStrokeContext);

export fn getTrieRoot(app: *App, mode: u8) ?*TrieNode {
    const settings = app.settings;

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

export fn createEditor(project: *Project, layer_ptr: *anyopaque) ?*Editor {
    return Editor.create(project, global.state.alloc, layer_ptr) catch null;
}

export fn resizeEditor(editor: *Editor, width: u32, height: u32) void {
    _ = editor.editor_thread.mailbox.push(.{ .resize = .{
        .height = height,
        .width = width,
    } }, .instant);

    editor.editor_thread.wakeup.notify() catch {};
}

export fn destroyEditor(editor: *Editor) void {
    editor.destroy();
}

export fn setEditorVisibility(editor: *Editor, visible: bool) void {
    editor.setVisibility(visible) catch {};
}

export fn selectEditorEntry(editor: *Editor, id: u64) void {
    _ = editor.editor_thread.mailbox.push(.{ .select_entry = id }, .instant);

    editor.editor_thread.wakeup.notify() catch {};
}

export fn editorScrollTo(editor: *Editor, row: u64) void {
    _ = editor.editor_thread.mailbox.push(.{ .scroll = row }, .instant);

    editor.editor_thread.wakeup.notify() catch {};
}

pub const ExternBufferState = extern struct {
    entry_id: u64,
    row_count: u64,
};

export fn readBufferState(editor: *Editor, out: *ExternBufferState) bool {
    const buffer = editor.buffer orelse return false;
    if (buffer.getState() != .ready) return false;
    buffer.mutex.lock();
    defer buffer.mutex.unlock();
    const text = buffer.text orelse return false;
    out.* = .{
        .entry_id = buffer.entry_id,
        .row_count = text.rowCount,
    };
    return true;
}

test {
    _ = @import("keymaps/mod.zig");
    _ = @import("monitor/mod.zig");
    _ = @import("worktree/mod.zig");
}
