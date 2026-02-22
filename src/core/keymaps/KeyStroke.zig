const std = @import("std");

pub const Modifiers = packed struct(u8) {
    shift: bool = false,
    alt: bool = false,
    ctrl: bool = false,
    super: bool = false,
    hyper: bool = false,
    meta: bool = false,
    _padding: u2 = 0,
};

pub const named = struct {
    pub const escape: u21 = 0x1b;
    pub const enter: u21 = 0x0d;
    pub const tab: u21 = 0x09;
    pub const backspace: u21 = 0x7f;
    pub const space: u21 = 0x20;
    pub const delete: u21 = 0x10F000;
    pub const insert: u21 = 0x10F001;
    pub const home: u21 = 0x10F002;
    pub const end: u21 = 0x10F003;
    pub const page_up: u21 = 0x10F004;
    pub const page_down: u21 = 0x10F005;
    pub const up: u21 = 0x10F006;
    pub const down: u21 = 0x10F007;
    pub const left: u21 = 0x10F008;
    pub const right: u21 = 0x10F009;
    pub const f1: u21 = 0x10F010;
    pub const f2: u21 = 0x10F011;
    pub const f3: u21 = 0x10F012;
    pub const f4: u21 = 0x10F013;
    pub const f5: u21 = 0x10F014;
    pub const f6: u21 = 0x10F015;
    pub const f7: u21 = 0x10F016;
    pub const f8: u21 = 0x10F017;
    pub const f9: u21 = 0x10F018;
    pub const f10: u21 = 0x10F019;
    pub const f11: u21 = 0x10F01A;
    pub const f12: u21 = 0x10F01B;
};

pub const name_map = std.StaticStringMap(u21).initComptime(.{
    .{ "escape", named.escape },
    .{ "esc", named.escape },
    .{ "enter", named.enter },
    .{ "return", named.enter },
    .{ "tab", named.tab },
    .{ "backspace", named.backspace },
    .{ "space", named.space },
    .{ "delete", named.delete },
    .{ "insert", named.insert },
    .{ "home", named.home },
    .{ "end", named.end },
    .{ "page_up", named.page_up },
    .{ "pageup", named.page_up },
    .{ "page_down", named.page_down },
    .{ "pagedown", named.page_down },
    .{ "up", named.up },
    .{ "down", named.down },
    .{ "left", named.left },
    .{ "right", named.right },
    .{ "f1", named.f1 },
    .{ "f2", named.f2 },
    .{ "f3", named.f3 },
    .{ "f4", named.f4 },
    .{ "f5", named.f5 },
    .{ "f6", named.f6 },
    .{ "f7", named.f7 },
    .{ "f8", named.f8 },
    .{ "f9", named.f9 },
    .{ "f10", named.f10 },
    .{ "f11", named.f11 },
    .{ "f12", named.f12 },
});

pub const KeyStroke = struct {
    codepoint: u21,
    mods: Modifiers,

    pub fn eql(a: KeyStroke, b: KeyStroke) bool {
        return a.codepoint == b.codepoint and @as(u8, @bitCast(a.mods)) == @as(u8, @bitCast(b.mods));
    }

    pub fn hash(self: KeyStroke) u32 {
        const cp_bytes = std.mem.asBytes(&self.codepoint);
        const mod_byte: u8 = @bitCast(self.mods);
        var buf: [cp_bytes.len + 1]u8 = undefined;
        @memcpy(buf[0..cp_bytes.len], cp_bytes);
        buf[cp_bytes.len] = mod_byte;
        return std.hash.CityHash32.hash(&buf);
    }
};

pub const KeyStrokeContext = struct {
    pub fn hash(_: @This(), k: KeyStroke) u32 {
        return k.hash();
    }
    pub fn eql(_: @This(), a: KeyStroke, b: KeyStroke, _: usize) bool {
        return KeyStroke.eql(a, b);
    }
};

pub const ParseError = error{
    EmptyStroke,
    EmptySequence,
    UnknownModifier,
    UnknownKey,
    InvalidUtf8,
};

pub fn parseSequence(alloc: std.mem.Allocator, s: []const u8) (ParseError || std.mem.Allocator.Error)![]KeyStroke {
    if (s.len == 0) return ParseError.EmptySequence;

    var list: std.ArrayListUnmanaged(KeyStroke) = .{};
    errdefer list.deinit(alloc);

    var it = std.mem.tokenizeAny(u8, s, " \t");
    while (it.next()) |tok| {
        try list.append(alloc, try parseStroke(tok));
    }

    if (list.items.len == 0) return ParseError.EmptySequence;
    return try list.toOwnedSlice(alloc);
}

fn parseStroke(tok: []const u8) ParseError!KeyStroke {
    if (tok.len == 0) return ParseError.EmptyStroke;

    var mods: Modifiers = .{};

    var parts: [8][]const u8 = undefined;
    var n: usize = 0;
    var seg_it = std.mem.splitScalar(u8, tok, '+');
    while (seg_it.next()) |p| {
        if (n >= parts.len) break;
        parts[n] = p;
        n += 1;
    }
    if (n == 0) return ParseError.EmptyStroke;

    if (n > 1) {
        for (parts[0 .. n - 1]) |m| {
            if (asciiEqlIgnoreCase(m, "ctrl")) {
                mods.ctrl = true;
            } else if (asciiEqlIgnoreCase(m, "alt")) {
                mods.alt = true;
            } else if (asciiEqlIgnoreCase(m, "shift")) {
                mods.shift = true;
            } else if (asciiEqlIgnoreCase(m, "super")) {
                mods.super = true;
            } else if (asciiEqlIgnoreCase(m, "hyper")) {
                mods.hyper = true;
            } else if (asciiEqlIgnoreCase(m, "meta")) {
                mods.meta = true;
            } else {
                return ParseError.UnknownModifier;
            }
        }
    }

    const key_part = parts[n - 1];
    if (key_part.len == 0) return ParseError.EmptyStroke;

    const cp = try parseKeyCodepoint(key_part);

    return .{ .codepoint = cp, .mods = mods };
}

fn parseKeyCodepoint(s: []const u8) ParseError!u21 {
    const key_name = if (s.len >= 2 and s[0] == '<' and s[s.len - 1] == '>')
        s[1 .. s.len - 1]
    else
        s;

    if (key_name.len == 0) return ParseError.EmptyStroke;

    var lower_buf: [32]u8 = undefined;
    if (key_name.len <= lower_buf.len) {
        const lower = toLowerSlice(key_name, &lower_buf);
        if (name_map.get(lower)) |cp| {
            return cp;
        }
    }

    const len = std.unicode.utf8ByteSequenceLength(key_name[0]) catch return ParseError.InvalidUtf8;
    if (len > key_name.len) return ParseError.InvalidUtf8;
    const cp = std.unicode.utf8Decode(key_name[0..len]) catch return ParseError.InvalidUtf8;
    if (len != key_name.len) return ParseError.UnknownKey;
    return cp;
}

fn asciiEqlIgnoreCase(a: []const u8, comptime b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ac, bc| {
        if (std.ascii.toLower(ac) != bc) return false;
    }
    return true;
}

fn toLowerSlice(s: []const u8, buf: []u8) []const u8 {
    for (s, 0..) |c, i| {
        buf[i] = std.ascii.toLower(c);
    }
    return buf[0..s.len];
}

const testing = std.testing;

test "parseStroke: single character" {
    const ks = try parseStroke("g");
    try testing.expectEqual(@as(u21, 'g'), ks.codepoint);
    try testing.expectEqual(@as(u8, 0), @as(u8, @bitCast(ks.mods)));
}

test "parseStroke: modifier + character" {
    const ks = try parseStroke("ctrl+t");
    try testing.expectEqual(@as(u21, 't'), ks.codepoint);
    try testing.expect(ks.mods.ctrl);
    try testing.expect(!ks.mods.shift);
}

test "parseStroke: multiple modifiers" {
    const ks = try parseStroke("ctrl+shift+x");
    try testing.expectEqual(@as(u21, 'x'), ks.codepoint);
    try testing.expect(ks.mods.ctrl);
    try testing.expect(ks.mods.shift);
}

test "parseStroke: named key" {
    const ks = try parseStroke("escape");
    try testing.expectEqual(@as(u21, 0x1b), ks.codepoint);
}

test "parseStroke: named key with angle brackets" {
    const ks = try parseStroke("<tab>");
    try testing.expectEqual(@as(u21, 0x09), ks.codepoint);
}

test "parseStroke: shift+tab" {
    const ks = try parseStroke("shift+tab");
    try testing.expectEqual(@as(u21, 0x09), ks.codepoint);
    try testing.expect(ks.mods.shift);
}

test "parseStroke: super modifier" {
    const ks = try parseStroke("super+l");
    try testing.expectEqual(@as(u21, 'l'), ks.codepoint);
    try testing.expect(ks.mods.super);
}

test "parseStroke: case-insensitive modifier" {
    const ks = try parseStroke("Ctrl+T");
    try testing.expectEqual(@as(u21, 'T'), ks.codepoint);
    try testing.expect(ks.mods.ctrl);
}

test "parseStroke: unknown modifier returns error" {
    try testing.expectError(ParseError.UnknownModifier, parseStroke("foo+t"));
}

test "parseSequence: single stroke" {
    const seq = try parseSequence(testing.allocator, "i");
    defer testing.allocator.free(seq);
    try testing.expectEqual(@as(usize, 1), seq.len);
    try testing.expectEqual(@as(u21, 'i'), seq[0].codepoint);
}

test "parseSequence: multi-stroke chord" {
    const seq = try parseSequence(testing.allocator, "g l");
    defer testing.allocator.free(seq);
    try testing.expectEqual(@as(usize, 2), seq.len);
    try testing.expectEqual(@as(u21, 'g'), seq[0].codepoint);
    try testing.expectEqual(@as(u21, 'l'), seq[1].codepoint);
}

test "parseSequence: modifier chord" {
    const seq = try parseSequence(testing.allocator, "ctrl+k ctrl+c");
    defer testing.allocator.free(seq);
    try testing.expectEqual(@as(usize, 2), seq.len);
    try testing.expect(seq[0].mods.ctrl);
    try testing.expectEqual(@as(u21, 'k'), seq[0].codepoint);
    try testing.expect(seq[1].mods.ctrl);
    try testing.expectEqual(@as(u21, 'c'), seq[1].codepoint);
}

test "parseSequence: empty string returns error" {
    try testing.expectError(ParseError.EmptySequence, parseSequence(testing.allocator, ""));
}

test "parseSequence: special keys" {
    const seq = try parseSequence(testing.allocator, "f1");
    defer testing.allocator.free(seq);
    try testing.expectEqual(named.f1, seq[0].codepoint);
}
