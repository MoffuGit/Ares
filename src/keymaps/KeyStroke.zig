const std = @import("std");
const vaxis = @import("vaxis");

const Key = vaxis.Key;
const Modifiers = Key.Modifiers;

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

/// Parses a key sequence string like "g l" or "ctrl+t" into a slice of KeyStrokes.
/// Strokes are separated by spaces. Each stroke is modifier+key joined by "+".
/// Caller owns the returned slice.
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

/// Parses a single stroke token like "ctrl+t", "g", "shift+tab", or "<esc>".
/// Modifiers: ctrl, alt, shift, super, hyper, meta (case-insensitive).
/// Key names: any vaxis.Key.name_map entry, or a single UTF-8 character.
fn parseStroke(tok: []const u8) ParseError!KeyStroke {
    if (tok.len == 0) return ParseError.EmptyStroke;

    var mods: Modifiers = .{};

    // Split by '+' — all parts except the last are modifiers, the last is the key.
    var parts: [8][]const u8 = undefined;
    var n: usize = 0;
    var seg_it = std.mem.splitScalar(u8, tok, '+');
    while (seg_it.next()) |p| {
        if (n >= parts.len) break;
        parts[n] = p;
        n += 1;
    }
    if (n == 0) return ParseError.EmptyStroke;

    // Parse modifier segments (all except the last)
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

/// Resolves a key name to its codepoint.
/// Supports: angle-bracket names like "<esc>", bare names like "tab",
/// and single UTF-8 characters like "g".
fn parseKeyCodepoint(s: []const u8) ParseError!u21 {
    // Strip angle brackets: "<esc>" → "esc"
    const name = if (s.len >= 2 and s[0] == '<' and s[s.len - 1] == '>')
        s[1 .. s.len - 1]
    else
        s;

    if (name.len == 0) return ParseError.EmptyStroke;

    // Try named key lookup via lowercase conversion
    var lower_buf: [32]u8 = undefined;
    if (name.len <= lower_buf.len) {
        const lower = toLowerSlice(name, &lower_buf);
        if (Key.name_map.get(lower)) |cp| {
            return cp;
        }
    }

    // Single UTF-8 character
    const len = std.unicode.utf8ByteSequenceLength(name[0]) catch return ParseError.InvalidUtf8;
    if (len > name.len) return ParseError.InvalidUtf8;
    const cp = std.unicode.utf8Decode(name[0..len]) catch return ParseError.InvalidUtf8;
    if (len != name.len) return ParseError.UnknownKey;
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

// ── Tests ──

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
    try testing.expectEqual(Key.f1, seq[0].codepoint);
}
