const std = @import("std");
const Allocator = std.mem.Allocator;
const Theme = @import("theme/mod.zig");
const keymapspkg = @import("../keymaps/mod.zig");
const Keymaps = keymapspkg.Keymaps;
const Action = keymapspkg.Action;
const KeyStroke = @import("../keymaps/KeyStroke.zig").KeyStroke;
const parseSequence = @import("../keymaps/KeyStroke.zig").parseSequence;

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

keymaps: Keymaps = .{ .normal = undefined, .insert = undefined, .visual = undefined },
keymaps_initialized: bool = false,
keymap_generation: u64 = 0,

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

pub fn load(self: *Settings, path: []const u8) LoadError!void {
    var settings_error: ?LoadError = null;

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

        if (self.dark_theme.ptr != DEFAULT_DARK.ptr) self.alloc.free(self.dark_theme);
        if (self.light_theme.ptr != DEFAULT_LIGHT.ptr) self.alloc.free(self.light_theme);

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
        const theme_names = [_][]const u8{
            self.light_theme,
            self.dark_theme,
        };

        for (theme_names) |name| {
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

        self.applyTheme();
    }

    if (settings_error) |err| return err;
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

    const DefaultEntry = struct { mode: keymapspkg.Mode, seq: []const KeyStroke, action: Action, binding: ?[]const u8 = null };
    const defaults = [_]DefaultEntry{
        .{ .mode = .normal, .seq = &.{.{ .codepoint = 'i', .mods = .{} }}, .action = .{ .workspace = .enter_insert }, .binding = "i" },
        .{ .mode = .normal, .seq = &.{.{ .codepoint = 'v', .mods = .{} }}, .action = .{ .workspace = .enter_visual }, .binding = "v" },
        .{ .mode = .insert, .seq = &.{.{ .codepoint = 0x1b, .mods = .{} }}, .action = .{ .workspace = .enter_normal }, .binding = "escape" },
        .{ .mode = .visual, .seq = &.{.{ .codepoint = 0x1b, .mods = .{} }}, .action = .{ .workspace = .enter_normal }, .binding = "escape" },
        .{ .mode = .normal, .seq = &.{.{ .codepoint = 'l', .mods = .{ .super = true } }}, .action = .{ .workspace = .toggle_left_dock }, .binding = "super+l" },
        .{ .mode = .normal, .seq = &.{.{ .codepoint = 't', .mods = .{ .ctrl = true } }}, .action = .{ .workspace = .new_tab }, .binding = "ctrl+t" },
        .{ .mode = .normal, .seq = &.{.{ .codepoint = '\t', .mods = .{} }}, .action = .{ .workspace = .next_tab }, .binding = "tab" },
        .{ .mode = .normal, .seq = &.{.{ .codepoint = '\t', .mods = .{ .shift = true } }}, .action = .{ .workspace = .prev_tab }, .binding = "shift+tab" },
        .{ .mode = .normal, .seq = &.{.{ .codepoint = 'q', .mods = .{ .ctrl = true } }}, .action = .{ .workspace = .close_active_tab }, .binding = "ctrl+q" },
        .{ .mode = .normal, .seq = &.{.{ .codepoint = 'k', .mods = .{ .super = true } }}, .action = .{ .workspace = .toggle_command_palette }, .binding = "super+k" },
        .{ .mode = .normal, .seq = &.{.{ .codepoint = 'k', .mods = .{} }}, .action = .{ .command = .up } },
        .{ .mode = .normal, .seq = &.{.{ .codepoint = 'j', .mods = .{} }}, .action = .{ .command = .down } },
        .{ .mode = .normal, .seq = &.{.{ .codepoint = '\r', .mods = .{} }}, .action = .{ .command = .select } },
        .{ .mode = .normal, .seq = &.{.{ .codepoint = 'u', .mods = .{ .ctrl = true } }}, .action = .{ .command = .scroll_up } },
        .{ .mode = .normal, .seq = &.{.{ .codepoint = 'd', .mods = .{ .ctrl = true } }}, .action = .{ .command = .scroll_down } },
        .{ .mode = .normal, .seq = &.{.{ .codepoint = 'g', .mods = .{} }, .{ .codepoint = 'g', .mods = .{} }}, .action = .{ .command = .top } },
        .{ .mode = .normal, .seq = &.{.{ .codepoint = 'G', .mods = .{ .shift = true } }}, .action = .{ .command = .bottom } },
    };

    for (defaults) |d| {
        self.keymaps.actions(d.mode).insert(d.seq, d.action) catch continue;
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
