const std = @import("std");
const xev = @import("../global.zig").xev;
const vaxis = @import("vaxis");
const Allocator = std.mem.Allocator;
const Theme = @import("theme/mod.zig");
const App = @import("../lib.zig").App;
const Context = App.Context;
const EventData = App.EventData;

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
};

alloc: Allocator,
context: *Context,

scheme: Scheme = .system,
system_scheme: vaxis.Color.Scheme = .dark,

themes: Themes = .{},

light_theme: []const u8 = DEFAULT_LIGHT,
dark_theme: []const u8 = DEFAULT_DARK,

theme: *const Theme = &Theme.fallback,

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
        const parsed = std.json.parseFromSlice(JsonSettings, self.alloc, str, .{}) catch {
            settings_error = LoadError.InvalidSettings;
            break :parse_settings;
        };
        defer parsed.deinit();

        const json_settings = parsed.value;
        self.dark_theme = self.alloc.dupe(u8, json_settings.dark_theme) catch DEFAULT_DARK;
        self.light_theme = self.alloc.dupe(u8, json_settings.light_theme) catch DEFAULT_LIGHT;
        self.scheme = std.meta.stringToEnum(Scheme, json_settings.appearance) orelse .system;
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

    const parsed = std.json.parseFromSlice(JsonSettings, s.alloc, json_str, .{}) catch return .rearm;
    defer parsed.deinit();

    const json_settings = parsed.value;

    if (s.dark_theme.len > 0) s.alloc.free(s.dark_theme);
    if (s.light_theme.len > 0) s.alloc.free(s.light_theme);

    s.dark_theme = s.alloc.dupe(u8, json_settings.dark_theme) catch "";
    s.light_theme = s.alloc.dupe(u8, json_settings.light_theme) catch "";
    s.scheme = std.meta.stringToEnum(Scheme, json_settings.appearance) orelse .system;

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
            existing.* = theme;
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

    try context.subscribe(.scheme, .{
        .userdata = self,
        .callback = schemeFn,
    });

    return self;
}

pub fn schemeFn(userdata: ?*anyopaque, data: EventData) void {
    const scheme = data.scheme;
    const self: *Settings = @ptrCast(@alignCast(userdata.?));

    self.updateSystemScheme(scheme);

    self.context.requestDraw();
}

pub fn destroy(self: *Settings) void {
    if (self.settings_path.len > 0) self.alloc.free(self.settings_path);
    if (self.dark_theme.len > 0) self.alloc.free(self.dark_theme);
    if (self.light_theme.len > 0) self.alloc.free(self.light_theme);
    var it = self.themes.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.name.len > 0) self.alloc.free(entry.value_ptr.name);
    }
    self.themes.deinit(self.alloc);
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
            if (entry.value_ptr.name.len > 0) alloc.free(entry.value_ptr.name);
        }
        settings.themes.deinit(alloc);
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
