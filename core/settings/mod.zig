const std = @import("std");
const global = @import("../global.zig");
const Allocator = std.mem.Allocator;
const keymapspkg = @import("../keymaps/mod.zig");
const Keymaps = keymapspkg.Keymaps;
const Monitor = @import("../monitor/mod.zig");
const Appearance = @import("../Appearance.zig");

pub const Settings = @This();

pub const Scheme = enum { light, dark, system };
pub const ColorScheme = enum { light, dark };
pub const TabsPosition = enum { horizontal, vertical };

const Themes = std.StringHashMapUnmanaged([]const u8);

const DEFAULT_DARK: []const u8 = "dark.json";
const DEFAULT_LIGHT: []const u8 = "light.json";

const FALLBACK_THEME_JSON: []const u8 =
    \\{"name":"fallback","colors":{},"theme":{"bg":"","fg":"","primaryBg":"","primaryFg":"","mutedBg":"","mutedFg":"","scrollThumb":"","scrollTrack":"","border":"","card":"","cardFg":"","popover":"","popoverFg":"","secondary":"","secondaryFg":"","accent":"","accentFg":"","destructive":"","destructiveFg":"","input":"","ring":"","chart1":"","chart2":"","chart3":"","chart4":"","chart5":"","sidebar":"","sidebarFg":"","sidebarPrimary":"","sidebarPrimaryFg":"","sidebarAccent":"","sidebarAccentFg":"","sidebarBorder":"","sidebarRing":""}}
;

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
    tabs_position: []const u8 = "horizontal",
    keymaps: ?std.json.Value = null,
};

alloc: Allocator,
mutex: std.Thread.Mutex = .{},

scheme: Scheme = .system,
system_scheme: ColorScheme = .dark,
tabs_position: TabsPosition = .horizontal,

themes: Themes = .{},

light_theme: []const u8 = DEFAULT_LIGHT,
dark_theme: []const u8 = DEFAULT_DARK,

theme_json: []const u8 = FALLBACK_THEME_JSON,

keymaps: Keymaps = undefined,
keymaps_initialized: bool = false,
keymap_generation: u64 = 0,

settings_path: []const u8 = "",

settings_watcher: u64 = 0,
theme_watcher: u64 = 0,

appearance: ?*Appearance = null,

pub fn create(alloc: Allocator) !*Settings {
    const self = try alloc.create(Settings);

    self.* = .{
        .alloc = alloc,
    };

    return self;
}

pub fn destroy(self: *Settings) void {
    if (self.settings_path.len > 0) self.alloc.free(self.settings_path);
    if (self.light_theme.len > 0 and self.light_theme.ptr != DEFAULT_LIGHT.ptr) self.alloc.free(self.light_theme);
    if (self.dark_theme.len > 0 and self.dark_theme.ptr != DEFAULT_DARK.ptr) self.alloc.free(self.dark_theme);
    var it = self.themes.iterator();
    while (it.next()) |entry| {
        self.alloc.free(entry.key_ptr.*);
        self.alloc.free(entry.value_ptr.*);
    }
    self.themes.deinit(self.alloc);
    if (self.keymaps_initialized) {
        self.keymaps.deinit();
    }
    self.alloc.destroy(self);
}

pub fn load(self: *Settings, path: []const u8, monitor: *Monitor, appe: ?*Appearance) !void {
    var dir = std.fs.openDirAbsolute(path, .{}) catch return LoadError.SettingsNotFound;
    defer dir.close();

    self.settings_path = self.alloc.dupe(u8, path) catch return LoadError.OutOfMemory;

    const themes_dir = try dir.realpathAlloc(self.alloc, "themes/");
    defer self.alloc.free(themes_dir);

    const settings_result = self.loadSettings(dir);

    try self.loadThemes(dir);

    try settings_result;

    global.state.emit(.settingsUpdate, .instant);

    if (appe) |a| {
        self.appearance = a;
        self.system_scheme = if (a.isDark()) .dark else .light;
        self.applyTheme();
        try a.observer.observe(.Change, .{
            .ctx = @ptrCast(self),
            .handle = appearanceChanged,
        });
    }

    self.settings_watcher = try monitor.watchPath(path, Settings, self, settingsCallback);
    self.theme_watcher = try monitor.watchPath(themes_dir, Settings, self, themeCallback);
}

fn appearanceChanged(ctx: *anyopaque, _: @import("../appearance/mac.zig").ObserverEvents) void {
    const self: *Settings = @ptrCast(@alignCast(ctx));
    self.mutex.lock();
    defer self.mutex.unlock();

    const a = self.appearance orelse return;
    self.system_scheme = if (a.isDark()) .dark else .light;
    self.applyThemeLocked();

    std.log.debug("scheme: {}", .{self.system_scheme});

    global.state.emit(.settingsUpdate, .instant);
}

fn settingsCallback(self: ?*Settings, _: u64, _: u32) void {
    const s = self orelse return;

    s.mutex.lock();
    defer s.mutex.unlock();

    var dir = std.fs.openDirAbsolute(s.settings_path, .{}) catch return;
    defer dir.close();

    s.loadSettings(dir) catch {};
    s.loadThemes(dir) catch {};

    global.state.emit(.settingsUpdate, .instant);
}
fn themeCallback(self: ?*Settings, _: u64, _: u32) void {
    const s = self orelse return;

    s.mutex.lock();
    defer s.mutex.unlock();

    var dir = std.fs.openDirAbsolute(s.settings_path, .{}) catch return;
    defer dir.close();

    s.loadThemes(dir) catch {};

    global.state.emit(.themeUpdate, .instant);
}

fn loadThemes(self: *Settings, dir: std.fs.Dir) LoadError!void {
    const theme_names = [_][]const u8{
        self.light_theme,
        self.dark_theme,
    };

    var themes_dir = dir.openDir("themes", .{}) catch null;
    defer if (themes_dir) |*d| d.close();

    for (theme_names) |name| {
        if (name.len == 0) continue;

        const td = themes_dir orelse continue;

        const theme_with_ext = std.mem.concat(self.alloc, u8, &.{ name, ".json" }) catch return LoadError.OutOfMemory;
        defer self.alloc.free(theme_with_ext);

        const theme_content = td.readFileAlloc(self.alloc, theme_with_ext, 1024 * 1024) catch continue;
        errdefer self.alloc.free(theme_content);

        const ThemeMeta = struct { name: []const u8 };
        const parsed = std.json.parseFromSlice(ThemeMeta, self.alloc, theme_content, .{ .ignore_unknown_fields = true }) catch {
            self.alloc.free(theme_content);
            continue;
        };
        defer parsed.deinit();

        const key = self.alloc.dupe(u8, parsed.value.name) catch {
            self.alloc.free(theme_content);
            continue;
        };

        if (self.themes.getPtr(key)) |existing| {
            self.alloc.free(existing.*);
            existing.* = theme_content;
            self.alloc.free(key);
        } else {
            self.themes.put(self.alloc, key, theme_content) catch {
                self.alloc.free(key);
                self.alloc.free(theme_content);
                continue;
            };
        }
    }

    self.applyThemeLocked();
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
    self.tabs_position = std.meta.stringToEnum(TabsPosition, json_settings.tabs_position) orelse .horizontal;

    if (json_settings.keymaps) |km_json| {
        std.log.debug("keymaps found in settings JSON, loading...", .{});
        self.loadKeymaps(km_json);
        std.log.debug("keymaps loaded, initialized={}, normal trie root children={}", .{
            self.keymaps_initialized,
            if (self.keymaps_initialized) self.keymaps.trie(.normal).root.childrens.count() else 0,
        });
    } else {
        std.log.debug("no keymaps in settings JSON", .{});
    }

    if (!self.keymaps_initialized) {
        std.log.debug("keymaps not initialized, loading defaults", .{});
        self.loadDefaultKeymaps();
        std.log.debug("defaults loaded, normal trie root children={}", .{
            self.keymaps.trie(.normal).root.childrens.count(),
        });
    }
}

pub fn applyTheme(self: *Settings) void {
    self.mutex.lock();
    defer self.mutex.unlock();
    self.applyThemeLocked();
}

fn applyThemeLocked(self: *Settings) void {
    const dark = self.scheme == .dark or (self.scheme == .system and self.system_scheme == .dark);
    const name = if (dark) self.dark_theme else self.light_theme;
    self.theme_json = self.themes.get(name) orelse FALLBACK_THEME_JSON;
}

pub fn setSystemScheme(self: *Settings, scheme: ColorScheme) void {
    self.mutex.lock();
    defer self.mutex.unlock();
    self.system_scheme = scheme;
    self.applyThemeLocked();
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

    var it = bindings.iterator();
    while (it.next()) |entry| {
        const seq_str = entry.key_ptr.*;
        const action_str = switch (entry.value_ptr.*) {
            .string => |s| s,
            else => continue,
        };

        self.keymaps.insert(scope, mode, seq_str, action_str) catch continue;
    }
}

fn loadDefaultKeymaps(self: *Settings) void {
    if (self.keymaps_initialized) {
        self.keymaps.deinit();
    }
    self.keymaps = Keymaps.init(self.alloc) catch return;
    self.keymaps_initialized = true;

    const DefaultEntry = struct {
        scope: keymapspkg.Scope,
        mode: keymapspkg.Mode,
        sequence: []const u8,
        action: []const u8,
    };

    const defaults = [_]DefaultEntry{
        .{ .scope = .global, .mode = .normal, .sequence = "i", .action = "workspace:enter_insert" },
        .{ .scope = .global, .mode = .normal, .sequence = "v", .action = "workspace:enter_visual" },
        .{ .scope = .global, .mode = .insert, .sequence = "escape", .action = "workspace:enter_normal" },
        .{ .scope = .global, .mode = .visual, .sequence = "escape", .action = "workspace:enter_normal" },
        .{ .scope = .global, .mode = .normal, .sequence = "super+l", .action = "workspace:toggle_left_dock" },
        .{ .scope = .global, .mode = .normal, .sequence = "ctrl+t", .action = "workspace:new_tab" },
        .{ .scope = .global, .mode = .normal, .sequence = "tab", .action = "workspace:next_tab" },
        .{ .scope = .global, .mode = .normal, .sequence = "shift+tab", .action = "workspace:prev_tab" },
        .{ .scope = .global, .mode = .normal, .sequence = "ctrl+q", .action = "workspace:close_active_tab" },
        .{ .scope = .global, .mode = .normal, .sequence = "super+k", .action = "workspace:toggle_command_palette" },
        .{ .scope = .command_palette, .mode = .normal, .sequence = "k", .action = "command:up" },
        .{ .scope = .command_palette, .mode = .normal, .sequence = "j", .action = "command:down" },
        .{ .scope = .command_palette, .mode = .normal, .sequence = "enter", .action = "command:select" },
        .{ .scope = .command_palette, .mode = .normal, .sequence = "ctrl+u", .action = "command:scroll_up" },
        .{ .scope = .command_palette, .mode = .normal, .sequence = "ctrl+d", .action = "command:scroll_down" },
        .{ .scope = .command_palette, .mode = .normal, .sequence = "g g", .action = "command:top" },
        .{ .scope = .command_palette, .mode = .normal, .sequence = "shift+G", .action = "command:bottom" },
    };

    for (defaults) |d| {
        self.keymaps.insert(d.scope, d.mode, d.sequence, d.action) catch continue;
    }

    self.keymap_generation +%= 1;
}

test "loadSettings parses settings.json" {
    const alloc = std.testing.allocator;
    var self = Settings{
        .alloc = alloc,
    };
    defer {
        if (self.light_theme.ptr != DEFAULT_LIGHT.ptr) alloc.free(self.light_theme);
        if (self.dark_theme.ptr != DEFAULT_DARK.ptr) alloc.free(self.dark_theme);
        if (self.keymaps_initialized) self.keymaps.deinit();
    }

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const json =
        \\{"appearance":"dark","light_theme":"my_light","dark_theme":"my_dark","tabs_position":"vertical"}
    ;
    tmp.dir.writeFile(.{ .sub_path = "settings.json", .data = json }) catch unreachable;

    self.loadSettings(tmp.dir) catch |err| {
        std.debug.panic("loadSettings failed: {}", .{err});
    };

    try std.testing.expectEqual(Scheme.dark, self.scheme);
    try std.testing.expectEqual(TabsPosition.vertical, self.tabs_position);
    try std.testing.expectEqualStrings("my_light", self.light_theme);
    try std.testing.expectEqualStrings("my_dark", self.dark_theme);
    try std.testing.expect(self.keymaps_initialized);
}

test "loadSettings returns error for missing settings.json" {
    const alloc = std.testing.allocator;
    var self = Settings{
        .alloc = alloc,
    };

    defer {
        if (self.keymaps_initialized) self.keymaps.deinit();
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

    defer {
        if (self.keymaps_initialized) self.keymaps.deinit();
    }

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    tmp.dir.writeFile(.{ .sub_path = "settings.json", .data = "not valid json" }) catch unreachable;

    const result = self.loadSettings(tmp.dir);
    try std.testing.expectError(error.SyntaxError, result);
}
