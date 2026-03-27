const std = @import("std");

pub const Theme = @This();

pub const Color = [4]u8;

name: []const u8 = "",
bg: Color,
fg: Color,
primaryBg: Color,
primaryFg: Color,
mutedBg: Color,
mutedFg: Color,
scrollThumb: Color,
scrollTrack: Color,
border: Color,
card: Color,
cardFg: Color,
popover: Color,
popoverFg: Color,
secondary: Color,
secondaryFg: Color,
accent: Color,
accentFg: Color,
destructive: Color,
destructiveFg: Color,
input: Color,
ring: Color,
chart1: Color,
chart2: Color,
chart3: Color,
chart4: Color,
chart5: Color,
sidebar: Color,
sidebarFg: Color,
sidebarPrimary: Color,
sidebarPrimaryFg: Color,
sidebarAccent: Color,
sidebarAccentFg: Color,
sidebarBorder: Color,
sidebarRing: Color,
modeNormal: Color,
modeVisual: Color,
modeInsert: Color,
fileType: std.StringHashMapUnmanaged(Color) = .{},

pub const fallback = Theme{
    .name = "fallback",
    .bg = Color{ 255, 30, 30, 255 },
    .fg = Color{ 220, 220, 220, 255 },
    .primaryBg = Color{ 40, 40, 40, 255 },
    .primaryFg = Color{ 200, 200, 200, 255 },
    .mutedBg = Color{ 60, 60, 60, 255 },
    .mutedFg = Color{ 160, 160, 160, 255 },
    .scrollThumb = Color{ 100, 100, 100, 255 },
    .scrollTrack = Color{ 50, 50, 50, 255 },
    .border = Color{ 0, 255, 0, 255 },
    .card = Color{ 255, 30, 30, 255 },
    .cardFg = Color{ 220, 220, 220, 255 },
    .popover = Color{ 255, 30, 30, 255 },
    .popoverFg = Color{ 220, 220, 220, 255 },
    .secondary = Color{ 60, 60, 60, 255 },
    .secondaryFg = Color{ 160, 160, 160, 255 },
    .accent = Color{ 60, 60, 60, 255 },
    .accentFg = Color{ 160, 160, 160, 255 },
    .destructive = Color{ 220, 38, 38, 255 },
    .destructiveFg = Color{ 255, 255, 255, 255 },
    .input = Color{ 50, 50, 50, 255 },
    .ring = Color{ 40, 40, 40, 255 },
    .chart1 = Color{ 231, 111, 81, 255 },
    .chart2 = Color{ 42, 157, 143, 255 },
    .chart3 = Color{ 233, 196, 106, 255 },
    .chart4 = Color{ 167, 139, 250, 255 },
    .chart5 = Color{ 244, 132, 95, 255 },
    .sidebar = Color{ 60, 60, 60, 255 },
    .sidebarFg = Color{ 220, 220, 220, 255 },
    .sidebarPrimary = Color{ 40, 40, 40, 255 },
    .sidebarPrimaryFg = Color{ 200, 200, 200, 255 },
    .sidebarAccent = Color{ 60, 60, 60, 255 },
    .sidebarAccentFg = Color{ 160, 160, 160, 255 },
    .sidebarBorder = Color{ 50, 50, 50, 255 },
    .sidebarRing = Color{ 40, 40, 40, 255 },
    .modeNormal = Color{ 40, 40, 40, 255 },
    .modeVisual = Color{ 60, 40, 80, 255 },
    .modeInsert = Color{ 40, 60, 80, 255 },
};

pub fn getFileTypeColor(self: Theme, key: []const u8) Color {
    return self.fileType.get(key) orelse self.fileType.get("default").?;
}

pub fn deinit(self: *Theme, allocator: std.mem.Allocator) void {
    allocator.free(self.name);
    var it = self.fileType.keyIterator();
    while (it.next()) |key| {
        allocator.free(key.*);
    }
    self.fileType.deinit(allocator);
}

pub const ParseError = error{
    InvalidRgba,
    ColorNotFound,
    MissingField,
    InvalidJson,
};

const JsonTheme = struct {
    name: []const u8,
    colors: std.json.ArrayHashMap([]const u8),
    theme: struct {
        bg: []const u8,
        fg: []const u8,
        primaryBg: []const u8,
        primaryFg: []const u8,
        mutedBg: []const u8,
        mutedFg: []const u8,
        scrollThumb: []const u8,
        scrollTrack: []const u8,
        border: []const u8,
        card: []const u8,
        cardFg: []const u8,
        popover: []const u8,
        popoverFg: []const u8,
        secondary: []const u8,
        secondaryFg: []const u8,
        accent: []const u8,
        accentFg: []const u8,
        destructive: []const u8,
        destructiveFg: []const u8,
        input: []const u8,
        ring: []const u8,
        chart1: []const u8,
        chart2: []const u8,
        chart3: []const u8,
        chart4: []const u8,
        chart5: []const u8,
        sidebar: []const u8,
        sidebarFg: []const u8,
        sidebarPrimary: []const u8,
        sidebarPrimaryFg: []const u8,
        sidebarAccent: []const u8,
        sidebarAccentFg: []const u8,
        sidebarBorder: []const u8,
        sidebarRing: []const u8,
        modeNormal: []const u8,
        modeVisual: []const u8,
        modeInsert: []const u8,
        fileType: ?std.json.ArrayHashMap([]const u8) = null,
    },
};

pub fn parse(allocator: std.mem.Allocator, json: []const u8) ParseError!Theme {
    const parsed = std.json.parseFromSlice(JsonTheme, allocator, json, .{}) catch {
        return ParseError.InvalidJson;
    };
    defer parsed.deinit();

    const json_theme = parsed.value;
    var colors = std.StringHashMap(Color).init(allocator);
    defer colors.deinit();

    var it = json_theme.colors.map.iterator();
    while (it.next()) |entry| {
        const color = parseHexColor(entry.value_ptr.*) catch return ParseError.InvalidRgba;
        colors.put(entry.key_ptr.*, color) catch return ParseError.InvalidRgba;
    }

    const bg = colors.get(json_theme.theme.bg) orelse return ParseError.ColorNotFound;
    const fg = colors.get(json_theme.theme.fg) orelse return ParseError.ColorNotFound;
    const primaryBg = colors.get(json_theme.theme.primaryBg) orelse return ParseError.ColorNotFound;
    const primaryFg = colors.get(json_theme.theme.primaryFg) orelse return ParseError.ColorNotFound;
    const mutedBg = colors.get(json_theme.theme.mutedBg) orelse return ParseError.ColorNotFound;
    const mutedFg = colors.get(json_theme.theme.mutedFg) orelse return ParseError.ColorNotFound;
    const scrollThumb = colors.get(json_theme.theme.scrollThumb) orelse return ParseError.ColorNotFound;
    const scrollTrack = colors.get(json_theme.theme.scrollTrack) orelse return ParseError.ColorNotFound;
    const border = colors.get(json_theme.theme.border) orelse return ParseError.ColorNotFound;
    const card = colors.get(json_theme.theme.card) orelse return ParseError.ColorNotFound;
    const cardFg = colors.get(json_theme.theme.cardFg) orelse return ParseError.ColorNotFound;
    const popover = colors.get(json_theme.theme.popover) orelse return ParseError.ColorNotFound;
    const popoverFg = colors.get(json_theme.theme.popoverFg) orelse return ParseError.ColorNotFound;
    const secondary = colors.get(json_theme.theme.secondary) orelse return ParseError.ColorNotFound;
    const secondaryFg = colors.get(json_theme.theme.secondaryFg) orelse return ParseError.ColorNotFound;
    const accent = colors.get(json_theme.theme.accent) orelse return ParseError.ColorNotFound;
    const accentFg = colors.get(json_theme.theme.accentFg) orelse return ParseError.ColorNotFound;
    const destructive = colors.get(json_theme.theme.destructive) orelse return ParseError.ColorNotFound;
    const destructiveFg = colors.get(json_theme.theme.destructiveFg) orelse return ParseError.ColorNotFound;
    const input = colors.get(json_theme.theme.input) orelse return ParseError.ColorNotFound;
    const ring = colors.get(json_theme.theme.ring) orelse return ParseError.ColorNotFound;
    const chart1 = colors.get(json_theme.theme.chart1) orelse return ParseError.ColorNotFound;
    const chart2 = colors.get(json_theme.theme.chart2) orelse return ParseError.ColorNotFound;
    const chart3 = colors.get(json_theme.theme.chart3) orelse return ParseError.ColorNotFound;
    const chart4 = colors.get(json_theme.theme.chart4) orelse return ParseError.ColorNotFound;
    const chart5 = colors.get(json_theme.theme.chart5) orelse return ParseError.ColorNotFound;
    const sidebar = colors.get(json_theme.theme.sidebar) orelse return ParseError.ColorNotFound;
    const sidebarFg = colors.get(json_theme.theme.sidebarFg) orelse return ParseError.ColorNotFound;
    const sidebarPrimary = colors.get(json_theme.theme.sidebarPrimary) orelse return ParseError.ColorNotFound;
    const sidebarPrimaryFg = colors.get(json_theme.theme.sidebarPrimaryFg) orelse return ParseError.ColorNotFound;
    const sidebarAccent = colors.get(json_theme.theme.sidebarAccent) orelse return ParseError.ColorNotFound;
    const sidebarAccentFg = colors.get(json_theme.theme.sidebarAccentFg) orelse return ParseError.ColorNotFound;
    const sidebarBorder = colors.get(json_theme.theme.sidebarBorder) orelse return ParseError.ColorNotFound;
    const sidebarRing = colors.get(json_theme.theme.sidebarRing) orelse return ParseError.ColorNotFound;
    const modeNormal = colors.get(json_theme.theme.modeNormal) orelse return ParseError.ColorNotFound;
    const modeVisual = colors.get(json_theme.theme.modeVisual) orelse return ParseError.ColorNotFound;
    const modeInsert = colors.get(json_theme.theme.modeInsert) orelse return ParseError.ColorNotFound;

    var file_type_colors = std.StringHashMapUnmanaged(Color){};
    errdefer {
        var ft_key_it = file_type_colors.keyIterator();
        while (ft_key_it.next()) |key| {
            allocator.free(key.*);
        }
        file_type_colors.deinit(allocator);
    }
    if (json_theme.theme.fileType) |ft| {
        var ft_it = ft.map.iterator();
        while (ft_it.next()) |entry| {
            const color = colors.get(entry.value_ptr.*) orelse return ParseError.ColorNotFound;
            const key = allocator.dupe(u8, entry.key_ptr.*) catch return ParseError.InvalidJson;
            file_type_colors.put(allocator, key, color) catch return ParseError.InvalidJson;
        }
        if (file_type_colors.get("default") == null) return ParseError.MissingField;
    }

    const name = allocator.dupe(u8, json_theme.name) catch return ParseError.InvalidJson;

    return Theme{
        .name = name,
        .bg = bg,
        .fg = fg,
        .primaryBg = primaryBg,
        .primaryFg = primaryFg,
        .mutedBg = mutedBg,
        .mutedFg = mutedFg,
        .scrollThumb = scrollThumb,
        .scrollTrack = scrollTrack,
        .border = border,
        .card = card,
        .cardFg = cardFg,
        .popover = popover,
        .popoverFg = popoverFg,
        .secondary = secondary,
        .secondaryFg = secondaryFg,
        .accent = accent,
        .accentFg = accentFg,
        .destructive = destructive,
        .destructiveFg = destructiveFg,
        .input = input,
        .ring = ring,
        .chart1 = chart1,
        .chart2 = chart2,
        .chart3 = chart3,
        .chart4 = chart4,
        .chart5 = chart5,
        .sidebar = sidebar,
        .sidebarFg = sidebarFg,
        .sidebarPrimary = sidebarPrimary,
        .sidebarPrimaryFg = sidebarPrimaryFg,
        .sidebarAccent = sidebarAccent,
        .sidebarAccentFg = sidebarAccentFg,
        .sidebarBorder = sidebarBorder,
        .sidebarRing = sidebarRing,
        .modeNormal = modeNormal,
        .modeVisual = modeVisual,
        .modeInsert = modeInsert,
        .fileType = file_type_colors,
    };
}

fn parseHexColor(hex_str: []const u8) !Color {
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

test "parse theme" {
    const json_str =
        \\{
        \\  "name": "dark",
        \\  "colors": {
        \\    "background": "#0a0a0a",
        \\    "foreground": "#eeeeeeff",
        \\    "scrollThumb": "#666666",
        \\    "scrollTrack": "#333333",
        \\    "primaryBg": "#1a1a1a",
        \\    "primaryFg": "#ffffff",
        \\    "mutedBg": "#2a2a2a",
        \\    "mutedFg": "#888888",
        \\    "destructive": "#dc2626",
        \\    "destructiveFg": "#ffffff",
        \\    "chart1": "#e76f51",
        \\    "chart2": "#2a9d8f",
        \\    "chart3": "#e9c46a",
        \\    "chart4": "#a78bfa",
        \\    "chart5": "#f4845f"
        \\  },
        \\  "theme": {
        \\    "bg": "background",
        \\    "fg": "foreground",
        \\    "primaryBg": "primaryBg",
        \\    "primaryFg": "primaryFg",
        \\    "mutedBg": "mutedBg",
        \\    "mutedFg": "mutedFg",
        \\    "scrollThumb": "scrollThumb",
        \\    "scrollTrack": "scrollTrack",
        \\    "border": "scrollTrack",
        \\    "card": "background",
        \\    "cardFg": "foreground",
        \\    "popover": "background",
        \\    "popoverFg": "foreground",
        \\    "secondary": "mutedBg",
        \\    "secondaryFg": "mutedFg",
        \\    "accent": "mutedBg",
        \\    "accentFg": "mutedFg",
        \\    "destructive": "destructive",
        \\    "destructiveFg": "destructiveFg",
        \\    "input": "scrollTrack",
        \\    "ring": "primaryBg",
        \\    "chart1": "chart1",
        \\    "chart2": "chart2",
        \\    "chart3": "chart3",
        \\    "chart4": "chart4",
        \\    "chart5": "chart5",
        \\    "sidebar": "mutedBg",
        \\    "sidebarFg": "foreground",
        \\    "sidebarPrimary": "primaryBg",
        \\    "sidebarPrimaryFg": "primaryFg",
        \\    "sidebarAccent": "mutedBg",
        \\    "sidebarAccentFg": "mutedFg",
        \\    "sidebarBorder": "scrollTrack",
        \\    "sidebarRing": "primaryBg",
        \\    "modeNormal": "primaryBg",
        \\    "modeVisual": "mutedBg",
        \\    "modeInsert": "mutedBg"
        \\  }
        \\}
    ;

    var theme = try Theme.parse(std.testing.allocator, json_str);
    defer theme.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("dark", theme.name);
    try std.testing.expectEqual(Color{ 10, 10, 10, 255 }, theme.bg);
    try std.testing.expectEqual(Color{ 238, 238, 238, 255 }, theme.fg);
    try std.testing.expectEqual(Color{ 26, 26, 26, 255 }, theme.primaryBg);
    try std.testing.expectEqual(Color{ 255, 255, 255, 255 }, theme.primaryFg);
    try std.testing.expectEqual(Color{ 42, 42, 42, 255 }, theme.mutedBg);
    try std.testing.expectEqual(Color{ 136, 136, 136, 255 }, theme.mutedFg);
    try std.testing.expectEqual(Color{ 102, 102, 102, 255 }, theme.scrollThumb);
    try std.testing.expectEqual(Color{ 51, 51, 51, 255 }, theme.scrollTrack);
    try std.testing.expectEqual(Color{ 10, 10, 10, 255 }, theme.card);
    try std.testing.expectEqual(Color{ 238, 238, 238, 255 }, theme.cardFg);
    try std.testing.expectEqual(Color{ 10, 10, 10, 255 }, theme.popover);
    try std.testing.expectEqual(Color{ 238, 238, 238, 255 }, theme.popoverFg);
    try std.testing.expectEqual(Color{ 42, 42, 42, 255 }, theme.secondary);
    try std.testing.expectEqual(Color{ 136, 136, 136, 255 }, theme.secondaryFg);
    try std.testing.expectEqual(Color{ 42, 42, 42, 255 }, theme.accent);
    try std.testing.expectEqual(Color{ 136, 136, 136, 255 }, theme.accentFg);
    try std.testing.expectEqual(Color{ 220, 38, 38, 255 }, theme.destructive);
    try std.testing.expectEqual(Color{ 255, 255, 255, 255 }, theme.destructiveFg);
    try std.testing.expectEqual(Color{ 51, 51, 51, 255 }, theme.input);
    try std.testing.expectEqual(Color{ 26, 26, 26, 255 }, theme.ring);
    try std.testing.expectEqual(Color{ 231, 111, 81, 255 }, theme.chart1);
    try std.testing.expectEqual(Color{ 42, 157, 143, 255 }, theme.chart2);
    try std.testing.expectEqual(Color{ 233, 196, 106, 255 }, theme.chart3);
    try std.testing.expectEqual(Color{ 167, 139, 250, 255 }, theme.chart4);
    try std.testing.expectEqual(Color{ 244, 132, 95, 255 }, theme.chart5);
    try std.testing.expectEqual(Color{ 42, 42, 42, 255 }, theme.sidebar);
    try std.testing.expectEqual(Color{ 238, 238, 238, 255 }, theme.sidebarFg);
    try std.testing.expectEqual(Color{ 26, 26, 26, 255 }, theme.sidebarPrimary);
    try std.testing.expectEqual(Color{ 255, 255, 255, 255 }, theme.sidebarPrimaryFg);
    try std.testing.expectEqual(Color{ 42, 42, 42, 255 }, theme.sidebarAccent);
    try std.testing.expectEqual(Color{ 136, 136, 136, 255 }, theme.sidebarAccentFg);
    try std.testing.expectEqual(Color{ 51, 51, 51, 255 }, theme.sidebarBorder);
    try std.testing.expectEqual(Color{ 26, 26, 26, 255 }, theme.sidebarRing);
    try std.testing.expectEqual(Color{ 26, 26, 26, 255 }, theme.modeNormal);
    try std.testing.expectEqual(Color{ 42, 42, 42, 255 }, theme.modeVisual);
    try std.testing.expectEqual(Color{ 42, 42, 42, 255 }, theme.modeInsert);
}

test "parse theme with fileType" {
    const json_str =
        \\{
        \\  "name": "dark",
        \\  "colors": {
        \\    "background": "#0a0a0a",
        \\    "foreground": "#eeeeee",
        \\    "scrollThumb": "#666666",
        \\    "scrollTrack": "#333333",
        \\    "primaryBg": "#1a1a1a",
        \\    "primaryFg": "#ffffff",
        \\    "mutedBg": "#2a2a2a",
        \\    "mutedFg": "#888888",
        \\    "rustColor": "#dea584",
        \\    "zigColor": "#f7a41d",
        \\    "defaultFileColor": "#cccccc",
        \\    "destructive": "#dc2626",
        \\    "destructiveFg": "#ffffff",
        \\    "chart1": "#e76f51",
        \\    "chart2": "#2a9d8f",
        \\    "chart3": "#e9c46a",
        \\    "chart4": "#a78bfa",
        \\    "chart5": "#f4845f"
        \\  },
        \\  "theme": {
        \\    "bg": "background",
        \\    "fg": "foreground",
        \\    "primaryBg": "primaryBg",
        \\    "primaryFg": "primaryFg",
        \\    "mutedBg": "mutedBg",
        \\    "mutedFg": "mutedFg",
        \\    "scrollThumb": "scrollThumb",
        \\    "scrollTrack": "scrollTrack",
        \\    "border": "scrollTrack",
        \\    "card": "background",
        \\    "cardFg": "foreground",
        \\    "popover": "background",
        \\    "popoverFg": "foreground",
        \\    "secondary": "mutedBg",
        \\    "secondaryFg": "mutedFg",
        \\    "accent": "mutedBg",
        \\    "accentFg": "mutedFg",
        \\    "destructive": "destructive",
        \\    "destructiveFg": "destructiveFg",
        \\    "input": "scrollTrack",
        \\    "ring": "primaryBg",
        \\    "chart1": "chart1",
        \\    "chart2": "chart2",
        \\    "chart3": "chart3",
        \\    "chart4": "chart4",
        \\    "chart5": "chart5",
        \\    "sidebar": "mutedBg",
        \\    "sidebarFg": "foreground",
        \\    "sidebarPrimary": "primaryBg",
        \\    "sidebarPrimaryFg": "primaryFg",
        \\    "sidebarAccent": "mutedBg",
        \\    "sidebarAccentFg": "mutedFg",
        \\    "sidebarBorder": "scrollTrack",
        \\    "sidebarRing": "primaryBg",
        \\    "modeNormal": "primaryBg",
        \\    "modeVisual": "mutedBg",
        \\    "modeInsert": "mutedBg",
        \\    "fileType": {
        \\      "default": "defaultFileColor",
        \\      "rust": "rustColor",
        \\      "zig": "zigColor"
        \\    }
        \\  }
        \\}
    ;

    var theme = try Theme.parse(std.testing.allocator, json_str);
    defer theme.deinit(std.testing.allocator);

    try std.testing.expectEqual(Color{ 222, 165, 132, 255 }, theme.getFileTypeColor("rust"));
    try std.testing.expectEqual(Color{ 247, 164, 29, 255 }, theme.getFileTypeColor("zig"));
    try std.testing.expectEqual(Color{ 204, 204, 204, 255 }, theme.getFileTypeColor("lua"));
    try std.testing.expectEqual(Color{ 26, 26, 26, 255 }, theme.modeNormal);
    try std.testing.expectEqual(Color{ 42, 42, 42, 255 }, theme.modeVisual);
    try std.testing.expectEqual(Color{ 42, 42, 42, 255 }, theme.modeInsert);
}

test "parse theme fileType missing fallback" {
    const json_str =
        \\{
        \\  "name": "dark",
        \\  "colors": {
        \\    "background": "#0a0a0a",
        \\    "foreground": "#eeeeee",
        \\    "scrollThumb": "#666666",
        \\    "scrollTrack": "#333333",
        \\    "primaryBg": "#1a1a1a",
        \\    "primaryFg": "#ffffff",
        \\    "mutedBg": "#2a2a2a",
        \\    "mutedFg": "#888888",
        \\    "rustColor": "#dea584",
        \\    "destructive": "#dc2626",
        \\    "destructiveFg": "#ffffff",
        \\    "chart1": "#e76f51",
        \\    "chart2": "#2a9d8f",
        \\    "chart3": "#e9c46a",
        \\    "chart4": "#a78bfa",
        \\    "chart5": "#f4845f"
        \\  },
        \\  "theme": {
        \\    "bg": "background",
        \\    "fg": "foreground",
        \\    "primaryBg": "primaryBg",
        \\    "primaryFg": "primaryFg",
        \\    "mutedBg": "mutedBg",
        \\    "mutedFg": "mutedFg",
        \\    "scrollThumb": "scrollThumb",
        \\    "scrollTrack": "scrollTrack",
        \\    "border": "scrollTrack",
        \\    "card": "background",
        \\    "cardFg": "foreground",
        \\    "popover": "background",
        \\    "popoverFg": "foreground",
        \\    "secondary": "mutedBg",
        \\    "secondaryFg": "mutedFg",
        \\    "accent": "mutedBg",
        \\    "accentFg": "mutedFg",
        \\    "destructive": "destructive",
        \\    "destructiveFg": "destructiveFg",
        \\    "input": "scrollTrack",
        \\    "ring": "primaryBg",
        \\    "chart1": "chart1",
        \\    "chart2": "chart2",
        \\    "chart3": "chart3",
        \\    "chart4": "chart4",
        \\    "chart5": "chart5",
        \\    "sidebar": "mutedBg",
        \\    "sidebarFg": "foreground",
        \\    "sidebarPrimary": "primaryBg",
        \\    "sidebarPrimaryFg": "primaryFg",
        \\    "sidebarAccent": "mutedBg",
        \\    "sidebarAccentFg": "mutedFg",
        \\    "sidebarBorder": "scrollTrack",
        \\    "sidebarRing": "primaryBg",
        \\    "modeNormal": "primaryBg",
        \\    "modeVisual": "mutedBg",
        \\    "modeInsert": "mutedBg",
        \\    "fileType": {
        \\      "rust": "rustColor"
        \\    }
        \\  }
        \\}
    ;

    const result = Theme.parse(std.testing.allocator, json_str);
    try std.testing.expectError(ParseError.MissingField, result);
}
