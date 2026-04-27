const std = @import("std");

pub const Color = [4]u8;
pub const Colors = std.StringHashMapUnmanaged(Color);

pub const ParseError = error{
    InvalidRgba,
    ColorNotFound,
    MissingField,
    InvalidJson,
};

pub const ParseColorsError = error{
    InvalidRgba,
    InvalidJson,
    OutOfMemory,
};

pub const ThemeRole = enum {
    bg,
    fg,
    primaryBg,
    primaryFg,
    mutedBg,
    mutedFg,
    gutter,
    scrollThumb,
    scrollTrack,
    border,
    card,
    cardFg,
    popover,
    popoverFg,
    secondary,
    secondaryFg,
    accent,
    accentFg,
    destructive,
    destructiveFg,
    input,
    ring,
    chart1,
    chart2,
    chart3,
    chart4,
    chart5,
    sidebar,
    sidebarFg,
    sidebarPrimary,
    sidebarPrimaryFg,
    sidebarAccent,
    sidebarAccentFg,
    sidebarBorder,
    sidebarRing,
    modeNormal,
    modeVisual,
    modeInsert,
};

/// Built-in fallback theme used whenever the active theme does not define a
/// role or fails to resolve. Every role has a sensible value so callers never
/// need to provide their own fallback.
pub const DEFAULT_THEME_COLORS: std.EnumArray(ThemeRole, Color) = .init(.{
    .bg = .{ 0x0c, 0x0c, 0x0c, 0xff },
    .fg = .{ 0xea, 0xea, 0xea, 0xff },
    .primaryBg = .{ 0x1f, 0x6f, 0xeb, 0xff },
    .primaryFg = .{ 0xff, 0xff, 0xff, 0xff },
    .mutedBg = .{ 0x1a, 0x1a, 0x1a, 0xff },
    .mutedFg = .{ 0x8b, 0x8b, 0x8b, 0xff },
    .gutter = .{ 0x6e, 0x6e, 0x6e, 0xff },
    .scrollThumb = .{ 0x44, 0x44, 0x44, 0xff },
    .scrollTrack = .{ 0x1a, 0x1a, 0x1a, 0xff },
    .border = .{ 0x2a, 0x2a, 0x2a, 0xff },
    .card = .{ 0x14, 0x14, 0x14, 0xff },
    .cardFg = .{ 0xea, 0xea, 0xea, 0xff },
    .popover = .{ 0x14, 0x14, 0x14, 0xff },
    .popoverFg = .{ 0xea, 0xea, 0xea, 0xff },
    .secondary = .{ 0x26, 0x26, 0x26, 0xff },
    .secondaryFg = .{ 0xea, 0xea, 0xea, 0xff },
    .accent = .{ 0x1f, 0x6f, 0xeb, 0xff },
    .accentFg = .{ 0xff, 0xff, 0xff, 0xff },
    .destructive = .{ 0xe5, 0x48, 0x4f, 0xff },
    .destructiveFg = .{ 0xff, 0xff, 0xff, 0xff },
    .input = .{ 0x1a, 0x1a, 0x1a, 0xff },
    .ring = .{ 0x1f, 0x6f, 0xeb, 0xff },
    .chart1 = .{ 0x1f, 0x6f, 0xeb, 0xff },
    .chart2 = .{ 0x2e, 0xa0, 0x43, 0xff },
    .chart3 = .{ 0xe3, 0xb3, 0x41, 0xff },
    .chart4 = .{ 0xe5, 0x48, 0x4f, 0xff },
    .chart5 = .{ 0xa3, 0x71, 0xf7, 0xff },
    .sidebar = .{ 0x10, 0x10, 0x10, 0xff },
    .sidebarFg = .{ 0xea, 0xea, 0xea, 0xff },
    .sidebarPrimary = .{ 0x1f, 0x6f, 0xeb, 0xff },
    .sidebarPrimaryFg = .{ 0xff, 0xff, 0xff, 0xff },
    .sidebarAccent = .{ 0x26, 0x26, 0x26, 0xff },
    .sidebarAccentFg = .{ 0xea, 0xea, 0xea, 0xff },
    .sidebarBorder = .{ 0x2a, 0x2a, 0x2a, 0xff },
    .sidebarRing = .{ 0x1f, 0x6f, 0xeb, 0xff },
    .modeNormal = .{ 0x1f, 0x6f, 0xeb, 0xff },
    .modeVisual = .{ 0xa3, 0x71, 0xf7, 0xff },
    .modeInsert = .{ 0x2e, 0xa0, 0x43, 0xff },
});

const JsonThemeColors = struct {
    colors: std.json.ArrayHashMap([]const u8),
};

/// Theme JSON schema. The `theme` block maps each canonical role to a palette
/// name found in the `colors` block. All role fields default to "" so partial
/// themes still parse — unspecified roles inherit from DEFAULT_THEME_COLORS at
/// resolve time.
pub const JsonTheme = struct {
    name: []const u8,
    colors: std.json.ArrayHashMap([]const u8),
    theme: struct {
        bg: []const u8 = "",
        fg: []const u8 = "",
        primaryBg: []const u8 = "",
        primaryFg: []const u8 = "",
        mutedBg: []const u8 = "",
        mutedFg: []const u8 = "",
        gutter: []const u8 = "",
        scrollThumb: []const u8 = "",
        scrollTrack: []const u8 = "",
        border: []const u8 = "",
        card: []const u8 = "",
        cardFg: []const u8 = "",
        popover: []const u8 = "",
        popoverFg: []const u8 = "",
        secondary: []const u8 = "",
        secondaryFg: []const u8 = "",
        accent: []const u8 = "",
        accentFg: []const u8 = "",
        destructive: []const u8 = "",
        destructiveFg: []const u8 = "",
        input: []const u8 = "",
        ring: []const u8 = "",
        chart1: []const u8 = "",
        chart2: []const u8 = "",
        chart3: []const u8 = "",
        chart4: []const u8 = "",
        chart5: []const u8 = "",
        sidebar: []const u8 = "",
        sidebarFg: []const u8 = "",
        sidebarPrimary: []const u8 = "",
        sidebarPrimaryFg: []const u8 = "",
        sidebarAccent: []const u8 = "",
        sidebarAccentFg: []const u8 = "",
        sidebarBorder: []const u8 = "",
        sidebarRing: []const u8 = "",
        modeNormal: []const u8 = "",
        modeVisual: []const u8 = "",
        modeInsert: []const u8 = "",
        fileType: ?std.json.ArrayHashMap([]const u8) = null,
    },
};

pub fn parseColors(allocator: std.mem.Allocator, json: []const u8) ParseColorsError!Colors {
    const parsed = std.json.parseFromSlice(JsonThemeColors, allocator, json, .{ .ignore_unknown_fields = true }) catch {
        return ParseColorsError.InvalidJson;
    };
    defer parsed.deinit();

    var colors: Colors = .{};
    errdefer {
        var it = colors.keyIterator();
        while (it.next()) |key| {
            allocator.free(key.*);
        }
        colors.deinit(allocator);
    }

    var it = parsed.value.colors.map.iterator();
    while (it.next()) |entry| {
        const key = allocator.dupe(u8, entry.key_ptr.*) catch return ParseColorsError.OutOfMemory;
        errdefer allocator.free(key);

        const color = parseColor(entry.value_ptr.*) catch return ParseColorsError.InvalidRgba;
        colors.put(allocator, key, color) catch return ParseColorsError.OutOfMemory;
    }

    return colors;
}

pub fn parseColor(hex_str: []const u8) !Color {
    const hex = if (hex_str.len > 0 and hex_str[0] == '#') hex_str[1..] else hex_str;

    if (hex.len == 6) {
        const r = std.fmt.parseInt(u8, hex[0..2], 16) catch return error.InvalidFormat;
        const g = std.fmt.parseInt(u8, hex[2..4], 16) catch return error.InvalidFormat;
        const b = std.fmt.parseInt(u8, hex[4..6], 16) catch return error.InvalidFormat;
        return Color{ r, g, b, 255 };
    } else if (hex.len == 8) {
        const r = std.fmt.parseInt(u8, hex[0..2], 16) catch return error.InvalidFormat;
        const g = std.fmt.parseInt(u8, hex[2..4], 16) catch return error.InvalidFormat;
        const b = std.fmt.parseInt(u8, hex[4..6], 16) catch return error.InvalidFormat;
        const a = std.fmt.parseInt(u8, hex[6..8], 16) catch return error.InvalidFormat;
        return Color{ r, g, b, a };
    }

    return error.InvalidFormat;
}
