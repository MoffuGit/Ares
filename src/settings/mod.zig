const std = @import("std");
const xev = @import("../global.zig").xev;
const Allocator = std.mem.Allocator;
const Theme = @import("theme/mod.zig");
const App = @import("../App.zig");

pub const Settings = @This();

pub const Scheme = enum { light, dark, system };
const Themes = std.StringHashMapUnmanaged(Theme);

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
};

alloc: Allocator,

scheme: Scheme = .system,

themes: Themes = .{},

light_theme: []const u8 = "",
dark_theme: []const u8 = "",

theme: *const Theme = &Theme.fallback,

watcher: xev.Watcher = .{},
fs: xev.FileSystem,

pub fn load(self: *Settings, path: []const u8, app: *App) LoadError!void {
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
        const parsed = std.json.parseFromSlice(JsonSettings, self.alloc, str, .{}) catch {
            settings_error = LoadError.InvalidSettings;
            break :parse_settings;
        };
        defer parsed.deinit();

        const json_settings = parsed.value;
        self.dark_theme = self.alloc.dupe(u8, json_settings.dark_theme) catch "";
        self.light_theme = self.alloc.dupe(u8, json_settings.light_theme) catch "";
        self.scheme = std.meta.stringToEnum(Scheme, json_settings.appearance) orelse .system;
    }

    {
        const themes = [_][]const u8{ self.light_theme, self.dark_theme, "dark", "light" };

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

        const theme_name = switch (self.scheme) {
            .dark => if (self.dark_theme.len == 0) "dark.json" else self.dark_theme,
            .light => if (self.light_theme.len == 0) "light.json" else self.light_theme,
            .system => switch (app.scheme) {
                .dark => if (self.dark_theme.len == 0) "dark.json" else self.dark_theme,
                .light => if (self.light_theme.len == 0) "light.json" else self.light_theme,
            },
        };

        self.theme = self.themes.getPtr(theme_name) orelse &Theme.fallback;
    }

    if (settings_error) |err| return err;
}

pub fn setAppearance(self: *Settings, appearance: Scheme, app: *App) void {
    self.scheme = appearance;
    self.updateTheme(app);
}

pub fn updateTheme(self: *Settings, app: *App) void {
    const theme_name = switch (self.scheme) {
        .dark => if (self.dark_theme.len == 0) "dark.josn" else self.dark_theme,
        .light => if (self.light_theme.len == 0) "light.josn" else self.light_theme,
        .system => switch (app.scheme) {
            .dark => if (self.dark_theme.len == 0) "dark.josn" else self.dark_theme,
            .light => if (self.light_theme.len == 0) "light.josn" else self.light_theme,
        },
    };

    self.theme = self.themes.getPtr(theme_name) orelse &Theme.fallback;
}

pub fn create(alloc: Allocator) !*Settings {
    const self = try alloc.create(Settings);
    errdefer alloc.destroy(self);

    var fs = xev.FileSystem.init();
    errdefer fs.deinit();

    self.* = .{
        .alloc = alloc,
        .fs = fs,
    };

    return self;
}

pub fn destroy(self: *Settings) void {
    if (self.dark_theme.len > 0) self.alloc.free(self.dark_theme);
    if (self.light_theme.len > 0) self.alloc.free(self.light_theme);
    self.themes.deinit(self.alloc);
    self.alloc.destroy(self);
}

test {
    _ = Theme;
}
