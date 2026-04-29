const std = @import("std");
const triepkg = @import("datastruct");
const keystrokepkg = @import("KeyStroke.zig");

const KeyStroke = keystrokepkg.KeyStroke;
const KeyStrokeContext = keystrokepkg.KeyStrokeContext;
pub const parseSequence = keystrokepkg.parseSequence;

pub const Dispatcher = @import("Dispatcher.zig");
pub const macos_keycodes = @import("macos_keycodes.zig");

const Allocator = std.mem.Allocator;
const KeySequenceTrie = triepkg.Trie(KeyStroke, u8, KeyStrokeContext);

pub const Mode = enum { normal, insert, visual };
pub const Scope = enum { global, editor, command_palette };

pub const Keymaps = struct {
    const scope_count = @typeInfo(Scope).@"enum".fields.len;
    const mode_count = @typeInfo(Mode).@"enum".fields.len;

    alloc: Allocator,
    tries: [mode_count]KeySequenceTrie,

    pub fn init(alloc: Allocator) !Keymaps {
        var tries: [mode_count]KeySequenceTrie = undefined;
        var initialized: usize = 0;
        errdefer for (tries[0..initialized]) |*t| t.deinit();

        for (&tries) |*t| {
            t.* = try KeySequenceTrie.init(alloc);
            initialized += 1;
        }

        return .{
            .alloc = alloc,
            .tries = tries,
        };
    }

    pub fn deinit(self: *Keymaps) void {
        for (&self.tries) |*t| t.deinit();
    }

    pub fn trie(self: *Keymaps, mode: Mode) *KeySequenceTrie {
        return &self.tries[@intFromEnum(mode)];
    }

    pub fn insert(self: *Keymaps, mode: Mode, sequence_str: []const u8) !void {
        const seq = try parseSequence(self.alloc, sequence_str);
        defer self.alloc.free(seq);

        const t = self.trie(mode);
        try t.insert(seq, 1);
    }

    /// Returns true if `sequence_str` is a complete, registered keymap
    /// (the trie node at this sequence is marked as terminal). Note that
    /// the trie may still have descendants past this point.
    pub fn isKeymap(self: *Keymaps, mode: Mode, sequence_str: []const u8) bool {
        const seq = parseSequence(self.alloc, sequence_str) catch return false;
        defer self.alloc.free(seq);

        const t = self.trie(mode);
        const node = t.get(seq) orelse return false;
        return node.values.items.len > 0;
    }

    /// Returns true if `sequence_str` is a strict prefix of any registered
    /// keymap (i.e. the trie can continue from here).
    pub fn hasContinuation(self: *Keymaps, mode: Mode, sequence_str: []const u8) bool {
        const seq = parseSequence(self.alloc, sequence_str) catch return false;
        defer self.alloc.free(seq);

        const t = self.trie(mode);
        const node = t.get(seq) orelse return false;
        return node.childrens.count() > 0;
    }
};

test {
    _ = keystrokepkg;
    _ = Dispatcher;
}
