const std = @import("std");
const xev = @import("../global.zig").xev;
const vaxis = @import("vaxis");
const Allocator = std.mem.Allocator;
const Theme = @import("theme/mod.zig");
const apppkg = @import("../app/mod.zig");
const Context = apppkg.Context;
const EventData = apppkg.EventData;
const keymapspkg = @import("../keymaps/mod.zig");
const Keymaps = keymapspkg.Keymaps;
const Action = keymapspkg.Action;
const KeyStroke = @import("../keymaps/KeyStroke.zig").KeyStroke;
const parseSequence = @import("../keymaps/KeyStroke.zig").parseSequence;

pub const Settings = @This();

pub const Scheme = enum { light, dark, system };

const Themes = std.StringHashMapUnmanaged(Theme);

const DEFAULT_DARK: []const u8 = "dark.json";
const DEFAULT_LIGHT: []const u8 = "light.json";

pub const LoadError = error{
    SettingsNotFound,
    ThemeNotFound,
    InvalidSettings,
    InvalidTheme,
    OutOfMemory,
};

const JsonSettings = struct {
    appearance: []const u8,
    light_theme: []const u8,
    dark_theme: []const u8,
    keymaps: ?std.json.Value = null,
};

alloc: Allocator,
context: *Context,

scheme: Scheme = .system,
system_scheme: vaxis.Color.Scheme = .dark,

themes: Themes = .{},

light_theme: []const u8 = DEFAULT_LIGHT,
dark_theme: []const u8 = DEFAULT_DARK,

theme: *const Theme = &Theme.fallback,

keymaps: Keymaps = .{ .normal = undefined, .insert = undefined, .visual = undefined },
keymaps_initialized: bool = false,
keymap_generation: u64 = 0,

settings_w: xev.FileSystem.Watcher = .{},
themes_w: xev.FileSystem.Watcher = .{},
fs: xev.FileSystem,
settings_path: []const u8 = "",

pub fn load(self: *Settings, path: []const u8) LoadError!void {
    var settings_error: ?LoadError = null;

    if (self.settings_path.len > 0) self.alloc.free(self.settings_path);
    self.settings_path = self.alloc.dupe(u8, path) catch return LoadError.OutOfMemory;

    const file = std.fs.path.join(self.alloc, &.{ path, "settings.json" }) catch return LoadError.OutOfMemory;
    defer self.alloc.free(file);

    const json_str = std.fs.cwd().readFileAlloc(self.alloc, file, 1024 * 1024) catch |err| blk: {
        settings_error = switch (err) {
            error.FileNotFound => LoadError.SettingsNotFound,
            else => LoadError.SettingsNotFound,
        };
        break :blk null;
    };
    defer if (json_str) |str| self.alloc.free(str);

    if (json_str) |str| parse_settings: {
        const parsed = std.json.parseFromSlice(JsonSettings, self.alloc, str, .{ .allocate = .alloc_always }) catch {
            settings_error = LoadError.InvalidSettings;
            break :parse_settings;
        };
        defer parsed.deinit();

        const json_settings = parsed.value;
        self.dark_theme = self.alloc.dupe(u8, json_settings.dark_theme) catch DEFAULT_DARK;
        self.light_theme = self.alloc.dupe(u8, json_settings.light_theme) catch DEFAULT_LIGHT;
        self.scheme = std.meta.stringToEnum(Scheme, json_settings.appearance) orelse .system;

        if (json_settings.keymaps) |km_json| {
            self.loadKeymaps(km_json);
        }
    }

    if (!self.keymaps_initialized) {
        self.loadDefaultKeymaps();
    }

    {
        const themes = [_][]const u8{
            self.light_theme,
            self.dark_theme,
        };

        for (themes) |name| {
            if (name.len == 0) continue;
            if (self.themes.get(name) != null) continue;

            const theme_file = std.fs.path.join(self.alloc, &.{ path, "themes", name }) catch return LoadError.OutOfMemory;
            defer self.alloc.free(theme_file);

            const theme_with_ext = std.mem.concat(self.alloc, u8, &.{ theme_file, ".json" }) catch return LoadError.OutOfMemory;
            defer self.alloc.free(theme_with_ext);

            const theme_content = std.fs.cwd().readFileAlloc(self.alloc, theme_with_ext, 1024 * 1024) catch continue;
            defer self.alloc.free(theme_content);

            const theme = Theme.parse(self.alloc, theme_content) catch continue;

            self.themes.put(self.alloc, theme.name, theme) catch continue;
        }

        self.theme = self.getTheme();
    }

    self.watch(&self.context.app.loop.loop);

    if (settings_error) |err| return err;
}

pub fn getTheme(self: *Settings) *const Theme {
    const dark = self.scheme == .dark or (self.scheme == .system and self.system_scheme == .dark);

    const name = if (dark) self.dark_theme else self.light_theme;

    return self.themes.getPtr(name) orelse &Theme.fallback;
}

pub fn updateSystemScheme(self: *Settings, scheme: vaxis.Color.Scheme) void {
    self.system_scheme = scheme;

    self.theme = self.getTheme();
}

fn loadKeymaps(self: *Settings, km_json: std.json.Value) void {
    const obj = switch (km_json) {
        .object => |o| o,
        else => return,
    };

    if (self.keymaps_initialized) {
        self.keymaps.deinit();
    }
    self.keymaps = Keymaps.init(self.alloc) catch return;
    self.keymaps_initialized = true;

    const mode_names = [_]struct { key: []const u8, mode: keymapspkg.Mode }{
        .{ .key = "normal", .mode = .normal },
        .{ .key = "insert", .mode = .insert },
        .{ .key = "visual", .mode = .visual },
    };

    for (mode_names) |entry| {
        if (obj.get(entry.key)) |mode_json| {
            self.loadKeymapMode(entry.mode, mode_json);
        }
    }

    self.keymap_generation +%= 1;
}

fn loadKeymapMode(self: *Settings, mode: keymapspkg.Mode, mode_json: std.json.Value) void {
    const bindings = switch (mode_json) {
        .object => |o| o,
        else => return,
    };
    const trie = self.keymaps.actions(mode);

    var it = bindings.iterator();
    while (it.next()) |entry| {
        const seq_str = entry.key_ptr.*;
        const action_str = switch (entry.value_ptr.*) {
            .string => |s| s,
            else => continue,
        };

        const action = std.meta.stringToEnum(Action, action_str) orelse continue;
        const seq = parseSequence(self.alloc, seq_str) catch continue;
        defer self.alloc.free(seq);

        trie.insert(seq, action) catch continue;
    }
}

fn loadDefaultKeymaps(self: *Settings) void {
    if (self.keymaps_initialized) {
        self.keymaps.deinit();
    }
    self.keymaps = Keymaps.init(self.alloc) catch return;
    self.keymaps_initialized = true;

    const defaults = [_]struct { mode: keymapspkg.Mode, seq: []const KeyStroke, action: Action }{
        .{ .mode = .normal, .seq = &.{.{ .codepoint = 'i', .mods = .{} }}, .action = .enter_insert },
        .{ .mode = .normal, .seq = &.{.{ .codepoint = 'v', .mods = .{} }}, .action = .enter_visual },
        .{ .mode = .insert, .seq = &.{.{ .codepoint = 0x1b, .mods = .{} }}, .action = .enter_normal },
        .{ .mode = .visual, .seq = &.{.{ .codepoint = 0x1b, .mods = .{} }}, .action = .enter_normal },
        .{ .mode = .normal, .seq = &.{.{ .codepoint = 'l', .mods = .{ .super = true } }}, .action = .toggle_left_dock },
        .{ .mode = .normal, .seq = &.{.{ .codepoint = 't', .mods = .{ .ctrl = true } }}, .action = .new_tab },
        .{ .mode = .normal, .seq = &.{.{ .codepoint = '\t', .mods = .{} }}, .action = .next_tab },
        .{ .mode = .normal, .seq = &.{.{ .codepoint = '\t', .mods = .{ .shift = true } }}, .action = .prev_tab },
        .{ .mode = .normal, .seq = &.{.{ .codepoint = 'q', .mods = .{ .ctrl = true } }}, .action = .close_active_tab },
        .{ .mode = .normal, .seq = &.{.{ .codepoint = 'k', .mods = .{ .super = true } }}, .action = .toggle_command_palette },
    };

    for (defaults) |d| {
        self.keymaps.actions(d.mode).insert(d.seq, d.action) catch continue;
    }

    self.keymap_generation +%= 1;
}

pub fn watch(self: *Settings, loop: *xev.Loop) void {
    if (self.settings_path.len == 0) return;

    self.fs.start(loop) catch return;

    self.fs.watch(self.settings_path, &self.settings_w, Settings, self, settingsCallback) catch {};

    const themes_path = std.fs.path.join(self.alloc, &.{ self.settings_path, "themes" }) catch return;
    defer self.alloc.free(themes_path);

    self.fs.watch(themes_path, &self.themes_w, Settings, self, themesCallback) catch {};
}

fn settingsCallback(
    self: ?*Settings,
    _: *xev.FileSystem.Watcher,
    _: []const u8,
    _: u32,
) xev.CallbackAction {
    const s = self orelse return .disarm;

    const file = std.fs.path.join(s.alloc, &.{ s.settings_path, "settings.json" }) catch return .rearm;
    defer s.alloc.free(file);

    const json_str = std.fs.cwd().readFileAlloc(s.alloc, file, 1024 * 1024) catch return .rearm;
    defer s.alloc.free(json_str);

    const parsed = std.json.parseFromSlice(JsonSettings, s.alloc, json_str, .{ .allocate = .alloc_always }) catch return .rearm;
    defer parsed.deinit();

    const json_settings = parsed.value;

    if (s.dark_theme.len > 0) s.alloc.free(s.dark_theme);
    if (s.light_theme.len > 0) s.alloc.free(s.light_theme);

    s.dark_theme = s.alloc.dupe(u8, json_settings.dark_theme) catch "";
    s.light_theme = s.alloc.dupe(u8, json_settings.light_theme) catch "";
    s.scheme = std.meta.stringToEnum(Scheme, json_settings.appearance) orelse .system;

    if (json_settings.keymaps) |km_json| {
        s.loadKeymaps(km_json);
    }

    s.theme = s.getTheme();
    s.context.requestDraw();

    return .rearm;
}

fn themesCallback(
    self: ?*Settings,
    _: *xev.FileSystem.Watcher,
    _: []const u8,
    _: u32,
) xev.CallbackAction {
    const s = self orelse return .disarm;

    const themes_to_reload = [_][]const u8{ s.light_theme, s.dark_theme };

    for (themes_to_reload) |name| {
        if (name.len == 0) continue;

        const theme_file = std.fs.path.join(s.alloc, &.{ s.settings_path, "themes", name }) catch continue;
        defer s.alloc.free(theme_file);

        const theme_with_ext = std.mem.concat(s.alloc, u8, &.{ theme_file, ".json" }) catch continue;
        defer s.alloc.free(theme_with_ext);

        const theme_content = std.fs.cwd().readFileAlloc(s.alloc, theme_with_ext, 1024 * 1024) catch continue;
        defer s.alloc.free(theme_content);

        var theme = Theme.parse(s.alloc, theme_content) catch continue;

        if (s.themes.getPtr(name)) |existing| {
            s.alloc.free(theme.name);
            theme.name = existing.name;
            var old_ft = existing.fileType;
            existing.* = theme;
            var ft_it = old_ft.keyIterator();
            while (ft_it.next()) |key| {
                s.alloc.free(key.*);
            }
            old_ft.deinit(s.alloc);
        } else {
            s.themes.put(s.alloc, theme.name, theme) catch {
                s.alloc.free(theme.name);
                continue;
            };
        }
    }

    s.theme = s.getTheme();
    s.context.requestDraw();

    s.context.app.loop.wakeup.notify() catch {};

    return .rearm;
}

pub fn create(alloc: Allocator, context: *Context) !*Settings {
    const self = try alloc.create(Settings);
    errdefer alloc.destroy(self);

    var fs = xev.FileSystem.init();
    errdefer fs.deinit();

    self.* = .{
        .context = context,
        .alloc = alloc,
        .fs = fs,
    };

    try context.subscribe(.scheme, Settings, self, schemeFn);

    return self;
}

pub fn schemeFn(self: *Settings, data: EventData) void {
    const scheme = data.scheme;

    self.updateSystemScheme(scheme);

    self.context.requestDraw();
}

pub fn destroy(self: *Settings) void {
    if (self.settings_path.len > 0) self.alloc.free(self.settings_path);
    if (self.dark_theme.len > 0) self.alloc.free(self.dark_theme);
    if (self.light_theme.len > 0) self.alloc.free(self.light_theme);
    var it = self.themes.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.deinit(self.alloc);
    }
    self.themes.deinit(self.alloc);
    if (self.keymaps_initialized) {
        self.keymaps.deinit();
    }
    self.fs.deinit();
    self.alloc.destroy(self);
}

test {
    _ = Theme;
}

test "load settings from settings folder" {
    const alloc = std.testing.allocator;

    var settings = Settings{
        .alloc = alloc,
        .fs = undefined,
        .themes = .{},
        .light_theme = "",
        .dark_theme = "",
        .scheme = .system,
        .theme = &Theme.fallback,
        .settings_w = .{},
        .themes_w = .{},
        .settings_path = "",
    };
    defer {
        if (settings.settings_path.len > 0) alloc.free(settings.settings_path);
        if (settings.dark_theme.len > 0) alloc.free(settings.dark_theme);
        if (settings.light_theme.len > 0) alloc.free(settings.light_theme);
        var it = settings.themes.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(alloc);
        }
        settings.themes.deinit(alloc);
        if (settings.keymaps_initialized) {
            settings.keymaps.deinit();
        }
    }

    settings.load("settings") catch |err| {
        std.debug.print("Load error: {}\n", .{err});
        return err;
    };

    try std.testing.expectEqual(.system, settings.scheme);
    try std.testing.expectEqualStrings("dark", settings.dark_theme);
    try std.testing.expectEqualStrings("light", settings.light_theme);

    const dark_theme = settings.themes.get("dark");
    try std.testing.expect(dark_theme != null);
    try std.testing.expectEqualStrings("dark", dark_theme.?.name);

    const light_theme = settings.themes.get("light");
    try std.testing.expect(light_theme != null);
    try std.testing.expectEqualStrings("light", light_theme.?.name);

    try std.testing.expect(settings.theme != &Theme.fallback);
}
