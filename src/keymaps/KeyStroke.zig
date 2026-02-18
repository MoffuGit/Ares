const std = @import("std");
const vaxis = @import("vaxis");

const Key = vaxis.Key;
const Modifiers = Key.Modifiers;

pub const KeyStroke = struct {
    codepoint: u21,
    mods: Modifiers,

    pub fn fromVaxisKey(key: vaxis.Key) KeyStroke {
        return .{
            .codepoint = @intCast(key.codepoint),
            .mods = key.mods,
        };
    }

    pub fn eql(a: KeyStroke, b: KeyStroke) bool {
        return a.codepoint == b.codepoint and @as(u8, @bitCast(a.mods)) == @as(u8, @bitCast(b.mods));
    }

    pub fn hash(self: KeyStroke) u64 {
        var h = std.hash.Wyhash.init(0);
        h.update(std.mem.asBytes(&self.codepoint));
        const mm: u8 = @bitCast(self.mods);
        h.update(&[_]u8{mm});
        return h.final();
    }
};

pub const KeyStrokeContext = struct {
    pub fn hash(_: @This(), k: KeyStroke) u64 {
        return k.hash();
    }
    pub fn eql(_: @This(), a: KeyStroke, b: KeyStroke) bool {
        return KeyStroke.eql(a, b);
    }
};
