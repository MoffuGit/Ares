const std = @import("std");
const Allocator = std.mem.Allocator;
const Theme = @import("theme/mod.zig");
const keymapspkg = @import("../keymaps/mod.zig");
const Keymaps = keymapspkg.Keymaps;
const Action = keymapspkg.Action;
const KeyStroke = @import("../keymaps/KeyStroke.zig").KeyStroke;
const parseSequence = @import("../keymaps/KeyStroke.zig").parseSequence;
const Monitor = @import("../monitor/mod.zig");

pub const Settings = @This();

pub const Scheme = enum { light, dark, system };
pub const ColorScheme = enum { light, dark };

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

scheme: Scheme = .system,
system_scheme: ColorScheme = .dark,

themes: Themes = .{},

light_theme: []const u8 = DEFAULT_LIGHT,
dark_theme: []const u8 = DEFAULT_DARK,

active_theme: Theme = Theme.fallback,
theme: *const Theme = &Theme.fallback,

keymaps: Keymaps = .{ .tries = undefined },
keymaps_initialized: bool = false,
keymap_generation: u64 = 0,

settings_watcher: u64 = 0,
theme_watcher: u64 = 0,

binding_map: std.AutoHashMapUnmanaged(u32, []const u8) = .{},

pub fn create(alloc: Allocator) !*Settings {
    const self = try alloc.create(Settings);

    self.* = .{
        .alloc = alloc,
    };
    self.theme = &self.active_theme;

    return self;
}

pub fn destroy(self: *Settings) void {
    if (self.light_theme.len > 0 and self.light_theme.ptr != DEFAULT_LIGHT.ptr) self.alloc.free(self.light_theme);
    if (self.dark_theme.len > 0 and self.dark_theme.ptr != DEFAULT_DARK.ptr) self.alloc.free(self.dark_theme);
    var it = self.themes.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.deinit(self.alloc);
    }
    self.themes.deinit(self.alloc);
    if (self.keymaps_initialized) {
        self.keymaps.deinit();
    }
    self.clearBindingMap();
    self.binding_map.deinit(self.alloc);
    self.alloc.destroy(self);
}

pub fn load(self: *Settings, path: []const u8, monitor: *Monitor) !void {
    var dir = std.fs.openDirAbsolute(path, .{}) catch return LoadError.SettingsNotFound;
    defer dir.close();

    self.settings_watcher = try monitor.watchPath(path, Settings, self, settingsCallback);

    const themes_dir = try dir.realpathAlloc(self.alloc, "themes/");
    defer self.alloc.free(themes_dir);

    const settings_error = self.loadSettings(dir);

    self.theme_watcher = try monitor.watchPath(themes_dir, Settings, self, themeCallback);

    try self.loadThemes(dir);

    if (settings_error) |err| return err;
}

fn settingsCallback(self: ?*Settings, watcher: u64, event: u32) void {}
fn themeCallback(self: ?*Settings, watcher: u64, event: u32) void {}

fn loadThemes(self: *Settings, dir: std.fs.Dir) LoadError!void {
    const theme_names = [_][]const u8{
        self.light_theme,
        self.dark_theme,
    };

    var themes_dir = dir.openDir("themes", .{}) catch null;
    defer if (themes_dir) |*d| d.close();

    for (theme_names) |name| {
        if (name.len == 0) continue;
        if (self.themes.get(name) != null) continue;

        const td = themes_dir orelse continue;

        const theme_with_ext = std.mem.concat(self.alloc, u8, &.{ name, ".json" }) catch return LoadError.OutOfMemory;
        defer self.alloc.free(theme_with_ext);

        const theme_content = td.readFileAlloc(self.alloc, theme_with_ext, 1024 * 1024) catch continue;
        defer self.alloc.free(theme_content);

        const theme = Theme.parse(self.alloc, theme_content) catch continue;

        self.themes.put(self.alloc, theme.name, theme) catch continue;
    }

    self.applyTheme();
}

fn loadSettings(self: *Settings, dir: std.fs.Dir) !void {
    const json_str = try dir.readFileAlloc(self.alloc, "settings.json", 1024 * 1024);
    defer self.alloc.free(json_str);

    const parsed = try std.json.parseFromSlice(JsonSettings, self.alloc, json_str, .{ .allocate = .alloc_always });
    defer parsed.deinit();

    const json_settings = parsed.value;

    if (self.dark_theme.ptr != DEFAULT_DARK.ptr) self.alloc.free(self.dark_theme);
    if (self.light_theme.ptr != DEFAULT_LIGHT.ptr) self.alloc.free(self.light_theme);

    self.dark_theme = self.alloc.dupe(u8, json_settings.dark_theme) catch DEFAULT_DARK;
    self.light_theme = self.alloc.dupe(u8, json_settings.light_theme) catch DEFAULT_LIGHT;
    self.scheme = std.meta.stringToEnum(Scheme, json_settings.appearance) orelse .system;

    if (json_settings.keymaps) |km_json| {
        self.loadKeymaps(km_json);
    }

    if (!self.keymaps_initialized) {
        self.loadDefaultKeymaps();
    }
}

pub fn getTheme(self: *Settings) *const Theme {
    const dark = self.scheme == .dark or (self.scheme == .system and self.system_scheme == .dark);

    const name = if (dark) self.dark_theme else self.light_theme;

    return self.themes.getPtr(name) orelse &Theme.fallback;
}

pub fn applyTheme(self: *Settings) void {
    const source = self.getTheme();
    self.active_theme = source.*;
    self.theme = &self.active_theme;
}

pub fn setSystemScheme(self: *Settings, scheme: ColorScheme) void {
    self.system_scheme = scheme;
    self.applyTheme();
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

    self.clearBindingMap();

    const scope_names = [_]struct { key: []const u8, scope: keymapspkg.Scope }{
        .{ .key = "global", .scope = .global },
        .{ .key = "editor", .scope = .editor },
        .{ .key = "command_palette", .scope = .command_palette },
    };

    const mode_names = [_]struct { key: []const u8, mode: keymapspkg.Mode }{
        .{ .key = "normal", .mode = .normal },
        .{ .key = "insert", .mode = .insert },
        .{ .key = "visual", .mode = .visual },
    };

    for (scope_names) |scope_entry| {
        if (obj.get(scope_entry.key)) |scope_json| {
            const scope_obj = switch (scope_json) {
                .object => |o| o,
                else => continue,
            };
            for (mode_names) |mode_entry| {
                if (scope_obj.get(mode_entry.key)) |mode_json| {
                    self.loadKeymapMode(scope_entry.scope, mode_entry.mode, mode_json);
                }
            }
        }
    }

    self.keymap_generation +%= 1;
}

fn loadKeymapMode(self: *Settings, scope: keymapspkg.Scope, mode: keymapspkg.Mode, mode_json: std.json.Value) void {
    const bindings = switch (mode_json) {
        .object => |o| o,
        else => return,
    };
    const trie = self.keymaps.actions(scope, mode);

    var it = bindings.iterator();
    while (it.next()) |entry| {
        const seq_str = entry.key_ptr.*;
        const action_str = switch (entry.value_ptr.*) {
            .string => |s| s,
            else => continue,
        };

        const action = Action.parse(action_str) orelse continue;
        const seq = parseSequence(self.alloc, seq_str) catch continue;
        defer self.alloc.free(seq);

        trie.insert(seq, action) catch continue;
        self.recordBinding(action, seq_str);
    }
}

fn loadDefaultKeymaps(self: *Settings) void {
    if (self.keymaps_initialized) {
        self.keymaps.deinit();
    }
    self.keymaps = Keymaps.init(self.alloc) catch return;
    self.keymaps_initialized = true;

    self.clearBindingMap();

    const DefaultEntry = struct { scope: keymapspkg.Scope, mode: keymapspkg.Mode, seq: []const KeyStroke, action: Action, binding: ?[]const u8 = null };
    const defaults = [_]DefaultEntry{
        .{ .scope = .global, .mode = .normal, .seq = &.{.{ .codepoint = 'i', .mods = .{} }}, .action = .{ .workspace = .enter_insert }, .binding = "i" },
        .{ .scope = .global, .mode = .normal, .seq = &.{.{ .codepoint = 'v', .mods = .{} }}, .action = .{ .workspace = .enter_visual }, .binding = "v" },
        .{ .scope = .global, .mode = .insert, .seq = &.{.{ .codepoint = 0x1b, .mods = .{} }}, .action = .{ .workspace = .enter_normal }, .binding = "escape" },
        .{ .scope = .global, .mode = .visual, .seq = &.{.{ .codepoint = 0x1b, .mods = .{} }}, .action = .{ .workspace = .enter_normal }, .binding = "escape" },
        .{ .scope = .global, .mode = .normal, .seq = &.{.{ .codepoint = 'l', .mods = .{ .super = true } }}, .action = .{ .workspace = .toggle_left_dock }, .binding = "super+l" },
        .{ .scope = .global, .mode = .normal, .seq = &.{.{ .codepoint = 't', .mods = .{ .ctrl = true } }}, .action = .{ .workspace = .new_tab }, .binding = "ctrl+t" },
        .{ .scope = .global, .mode = .normal, .seq = &.{.{ .codepoint = '\t', .mods = .{} }}, .action = .{ .workspace = .next_tab }, .binding = "tab" },
        .{ .scope = .global, .mode = .normal, .seq = &.{.{ .codepoint = '\t', .mods = .{ .shift = true } }}, .action = .{ .workspace = .prev_tab }, .binding = "shift+tab" },
        .{ .scope = .global, .mode = .normal, .seq = &.{.{ .codepoint = 'q', .mods = .{ .ctrl = true } }}, .action = .{ .workspace = .close_active_tab }, .binding = "ctrl+q" },
        .{ .scope = .global, .mode = .normal, .seq = &.{.{ .codepoint = 'k', .mods = .{ .super = true } }}, .action = .{ .workspace = .toggle_command_palette }, .binding = "super+k" },
        .{ .scope = .command_palette, .mode = .normal, .seq = &.{.{ .codepoint = 'k', .mods = .{} }}, .action = .{ .command = .up } },
        .{ .scope = .command_palette, .mode = .normal, .seq = &.{.{ .codepoint = 'j', .mods = .{} }}, .action = .{ .command = .down } },
        .{ .scope = .command_palette, .mode = .normal, .seq = &.{.{ .codepoint = '\r', .mods = .{} }}, .action = .{ .command = .select } },
        .{ .scope = .command_palette, .mode = .normal, .seq = &.{.{ .codepoint = 'u', .mods = .{ .ctrl = true } }}, .action = .{ .command = .scroll_up } },
        .{ .scope = .command_palette, .mode = .normal, .seq = &.{.{ .codepoint = 'd', .mods = .{ .ctrl = true } }}, .action = .{ .command = .scroll_down } },
        .{ .scope = .command_palette, .mode = .normal, .seq = &.{ .{ .codepoint = 'g', .mods = .{} }, .{ .codepoint = 'g', .mods = .{} } }, .action = .{ .command = .top } },
        .{ .scope = .command_palette, .mode = .normal, .seq = &.{.{ .codepoint = 'G', .mods = .{ .shift = true } }}, .action = .{ .command = .bottom } },
    };

    for (defaults) |d| {
        self.keymaps.actions(d.scope, d.mode).insert(d.seq, d.action) catch continue;
        if (d.binding) |b| self.recordBinding(d.action, b);
    }

    self.keymap_generation +%= 1;
}

fn recordBinding(self: *Settings, action: Action, seq_str: []const u8) void {
    const k = action.key();
    if (self.binding_map.contains(k)) return;
    const owned = self.alloc.dupe(u8, seq_str) catch return;
    self.binding_map.put(self.alloc, k, owned) catch {
        self.alloc.free(owned);
    };
}

fn clearBindingMap(self: *Settings) void {
    var it = self.binding_map.valueIterator();
    while (it.next()) |v| {
        self.alloc.free(v.*);
    }
    self.binding_map.clearRetainingCapacity();
}

pub fn keymapBindingString(self: *Settings, action: Action) ?[]const u8 {
    return self.binding_map.get(action.key());
}

test {
    _ = Theme;
}

test "loadSettings parses settings.json" {
    const alloc = std.testing.allocator;
    var self = Settings{
        .alloc = alloc,
    };
    self.theme = &self.active_theme;
    defer {
        if (self.light_theme.ptr != DEFAULT_LIGHT.ptr) alloc.free(self.light_theme);
        if (self.dark_theme.ptr != DEFAULT_DARK.ptr) alloc.free(self.dark_theme);
        if (self.keymaps_initialized) self.keymaps.deinit();
        self.clearBindingMap();
        self.binding_map.deinit(alloc);
    }

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const json =
        \\{"appearance":"dark","light_theme":"my_light","dark_theme":"my_dark"}
    ;
    tmp.dir.writeFile(.{ .sub_path = "settings.json", .data = json }) catch unreachable;

    self.loadSettings(tmp.dir) catch |err| {
        std.debug.panic("loadSettings failed: {}", .{err});
    };

    try std.testing.expectEqual(Scheme.dark, self.scheme);
    try std.testing.expectEqualStrings("my_light", self.light_theme);
    try std.testing.expectEqualStrings("my_dark", self.dark_theme);
    try std.testing.expect(self.keymaps_initialized);
}

test "loadSettings returns error for missing settings.json" {
    const alloc = std.testing.allocator;
    var self = Settings{
        .alloc = alloc,
    };
    self.theme = &self.active_theme;
    defer {
        if (self.keymaps_initialized) self.keymaps.deinit();
        self.clearBindingMap();
        self.binding_map.deinit(alloc);
    }

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const result = self.loadSettings(tmp.dir);
    try std.testing.expectError(error.FileNotFound, result);
}

test "loadSettings returns error for invalid json" {
    const alloc = std.testing.allocator;
    var self = Settings{
        .alloc = alloc,
    };
    self.theme = &self.active_theme;
    defer {
        if (self.keymaps_initialized) self.keymaps.deinit();
        self.clearBindingMap();
        self.binding_map.deinit(alloc);
    }

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    tmp.dir.writeFile(.{ .sub_path = "settings.json", .data = "not valid json" }) catch unreachable;

    const result = self.loadSettings(tmp.dir);
    try std.testing.expectError(error.SyntaxError, result);
}
