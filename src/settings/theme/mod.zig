const vaxis = @import("vaxis");
const std = @import("std");

pub const Theme = @This();

pub const Color = vaxis.Color;

name: []const u8 = "",
bg: Color,
fg: Color,

pub const fallback = Theme{
    .name = "fallback",
    .bg = Color{ .rgba = .{ 255, 30, 30, 255 } },
    .fg = Color{ .rgba = .{ 220, 220, 220, 255 } },
};

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

    const name = allocator.dupe(u8, json_theme.name) catch return ParseError.InvalidJson;

    return Theme{
        .name = name,
        .bg = bg,
        .fg = fg,
    };
}

fn parseHexColor(hex_str: []const u8) !Color {
    const hex = if (hex_str.len > 0 and hex_str[0] == '#') hex_str[1..] else hex_str;

    if (hex.len == 6) {
        const r = std.fmt.parseInt(u8, hex[0..2], 16) catch return error.InvalidFormat;
        const g = std.fmt.parseInt(u8, hex[2..4], 16) catch return error.InvalidFormat;
        const b = std.fmt.parseInt(u8, hex[4..6], 16) catch return error.InvalidFormat;
        return Color{ .rgba = .{ r, g, b, 255 } };
    } else if (hex.len == 8) {
        const r = std.fmt.parseInt(u8, hex[0..2], 16) catch return error.InvalidFormat;
        const g = std.fmt.parseInt(u8, hex[2..4], 16) catch return error.InvalidFormat;
        const b = std.fmt.parseInt(u8, hex[4..6], 16) catch return error.InvalidFormat;
        const a = std.fmt.parseInt(u8, hex[6..8], 16) catch return error.InvalidFormat;
        return Color{ .rgba = .{ r, g, b, a } };
    }

    return error.InvalidFormat;
}

test "parse theme" {
    const json_str =
        \\{
        \\  "name": "dark",
        \\  "colors": {
        \\    "background": "#0a0a0a",
        \\    "foreground": "#eeeeeeff"
        \\  },
        \\  "theme": {
        \\    "bg": "background",
        \\    "fg": "foreground"
        \\  }
        \\}
    ;

    const theme = try Theme.parse(std.testing.allocator, json_str);
    defer std.testing.allocator.free(theme.name);

    try std.testing.expectEqualStrings("dark", theme.name);
    try std.testing.expectEqual(Color{ .rgba = .{ 10, 10, 10, 255 } }, theme.bg);
    try std.testing.expectEqual(Color{ .rgba = .{ 238, 238, 238, 255 } }, theme.fg);
}
