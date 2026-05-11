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

pub const Mode = enum(u8) { normal, insert, visual };

/// Scopes group keymaps by UI surface. The native dispatcher resolves a
/// keystroke against the scopes that the JS side declared as currently
/// active (the focus stack). Order of declaration here is irrelevant to
/// runtime behaviour; precedence is decided by the focus stack alone.
pub const Scope = enum(u8) {
    global,
    editor,
    terminal,
    filetree,
    command_palette,
    lsp_completion,
    diff,
};

/// One entry on the focus stack. Bottom-first: the topmost (most recently
/// pushed) layer is the last element of the slice given to `dispatch`.
pub const FocusLayer = struct {
    scope: Scope,
    /// When non-null, replaces the editor's current `Mode` for the
    /// purpose of looking up keymaps. Topmost non-null wins.
    mode_override: ?Mode = null,
    /// When set, plain printable keys (no ctrl/alt/super/hyper/meta,
    /// not a named key) are NOT consumed: they fall through to the
    /// WebView so an `<input>`/contenteditable can receive them as text.
    /// Only the topmost layer's value matters.
    passthrough_printable: bool = false,
};

pub fn parseScope(name: []const u8) ?Scope {
    return std.meta.stringToEnum(Scope, name);
}

pub const Keymaps = struct {
    pub const scope_count = @typeInfo(Scope).@"enum".fields.len;
    pub const mode_count = @typeInfo(Mode).@"enum".fields.len;

    alloc: Allocator,
    tries: [scope_count][mode_count]KeySequenceTrie,

    pub fn init(alloc: Allocator) !Keymaps {
        var tries: [scope_count][mode_count]KeySequenceTrie = undefined;
        var done: usize = 0;
        errdefer {
            var i: usize = 0;
            outer: for (&tries) |*scope_tries| {
                for (scope_tries) |*t| {
                    if (i >= done) break :outer;
                    t.deinit();
                    i += 1;
                }
            }
        }

        for (&tries) |*scope_tries| {
            for (scope_tries) |*t| {
                t.* = try KeySequenceTrie.init(alloc);
                done += 1;
            }
        }

        return .{
            .alloc = alloc,
            .tries = tries,
        };
    }

    pub fn deinit(self: *Keymaps) void {
        for (&self.tries) |*scope_tries| {
            for (scope_tries) |*t| t.deinit();
        }
    }

    pub fn trie(self: *Keymaps, scope: Scope, mode: Mode) *KeySequenceTrie {
        return &self.tries[@intFromEnum(scope)][@intFromEnum(mode)];
    }

    pub fn insert(self: *Keymaps, scope: Scope, mode: Mode, sequence_str: []const u8) !void {
        const seq = try parseSequence(self.alloc, sequence_str);
        defer self.alloc.free(seq);

        const t = self.trie(scope, mode);
        try t.insert(seq, 1);
    }

    /// Returns true if `sequence_str` is a complete, registered keymap
    /// in (scope, mode).
    pub fn isKeymap(self: *Keymaps, scope: Scope, mode: Mode, sequence_str: []const u8) bool {
        const seq = parseSequence(self.alloc, sequence_str) catch return false;
        defer self.alloc.free(seq);

        const t = self.trie(scope, mode);
        const node = t.get(seq) orelse return false;
        return node.values.items.len > 0;
    }

    /// Returns true if `sequence_str` is a strict prefix of any registered
    /// keymap in (scope, mode).
    pub fn hasContinuation(self: *Keymaps, scope: Scope, mode: Mode, sequence_str: []const u8) bool {
        const seq = parseSequence(self.alloc, sequence_str) catch return false;
        defer self.alloc.free(seq);

        const t = self.trie(scope, mode);
        const node = t.get(seq) orelse return false;
        return node.childrens.count() > 0;
    }
};

test {
    _ = keystrokepkg;
    _ = Dispatcher;
}
