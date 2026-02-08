const vaxis = @import("vaxis");
const std = @import("std");

pub const Theme = @This();

pub const Color = vaxis.Color;

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
fileType: std.StringHashMapUnmanaged(Color) = .{},

pub const fallback = Theme{
    .name = "fallback",
    .bg = Color{ .rgba = .{ 255, 30, 30, 255 } },
    .fg = Color{ .rgba = .{ 220, 220, 220, 255 } },
    .primaryBg = Color{ .rgba = .{ 40, 40, 40, 255 } },
    .primaryFg = Color{ .rgba = .{ 200, 200, 200, 255 } },
    .mutedBg = Color{ .rgba = .{ 60, 60, 60, 255 } },
    .mutedFg = Color{ .rgba = .{ 160, 160, 160, 255 } },
    .scrollThumb = Color{ .rgba = .{ 100, 100, 100, 255 } },
    .scrollTrack = Color{ .rgba = .{ 50, 50, 50, 255 } },
    .border = Color{ .rgba = .{ 0, 255, 0, 255 } },
};

pub fn getFileTypeColor(self: Theme, key: []const u8) Color {
    return self.fileType.get(key) orelse self.fileType.get("default").?;
}

pub fn deinit(self: *Theme, allocator: std.mem.Allocator) void {
    allocator.free(self.name);
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

    var file_type_colors = std.StringHashMapUnmanaged(Color){};
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
        .fileType = file_type_colors,
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
        \\    "foreground": "#eeeeeeff",
        \\    "scrollThumb": "#666666",
        \\    "scrollTrack": "#333333",
        \\    "primaryBg": "#1a1a1a",
        \\    "primaryFg": "#ffffff",
        \\    "mutedBg": "#2a2a2a",
        \\    "mutedFg": "#888888"
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
        \\    "border": "scrollTrack"
        \\  }
        \\}
    ;

    var theme = try Theme.parse(std.testing.allocator, json_str);
    defer theme.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("dark", theme.name);
    try std.testing.expectEqual(Color{ .rgba = .{ 10, 10, 10, 255 } }, theme.bg);
    try std.testing.expectEqual(Color{ .rgba = .{ 238, 238, 238, 255 } }, theme.fg);
    try std.testing.expectEqual(Color{ .rgba = .{ 26, 26, 26, 255 } }, theme.primaryBg);
    try std.testing.expectEqual(Color{ .rgba = .{ 255, 255, 255, 255 } }, theme.primaryFg);
    try std.testing.expectEqual(Color{ .rgba = .{ 42, 42, 42, 255 } }, theme.mutedBg);
    try std.testing.expectEqual(Color{ .rgba = .{ 136, 136, 136, 255 } }, theme.mutedFg);
    try std.testing.expectEqual(Color{ .rgba = .{ 102, 102, 102, 255 } }, theme.scrollThumb);
    try std.testing.expectEqual(Color{ .rgba = .{ 51, 51, 51, 255 } }, theme.scrollTrack);
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
        \\    "defaultFileColor": "#cccccc"
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

    try std.testing.expectEqual(Color{ .rgba = .{ 222, 165, 132, 255 } }, theme.getFileTypeColor("rust"));
    try std.testing.expectEqual(Color{ .rgba = .{ 247, 164, 29, 255 } }, theme.getFileTypeColor("zig"));
    try std.testing.expectEqual(Color{ .rgba = .{ 204, 204, 204, 255 } }, theme.getFileTypeColor("lua"));
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
        \\    "rustColor": "#dea584"
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
        \\    "fileType": {
        \\      "rust": "rustColor"
        \\    }
        \\  }
        \\}
    ;

    const result = Theme.parse(std.testing.allocator, json_str);
    try std.testing.expectError(ParseError.MissingField, result);
}
