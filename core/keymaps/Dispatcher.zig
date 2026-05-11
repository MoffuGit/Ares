//! Stateful keymap dispatcher.
//!
//! Feed it `KeyStroke`s in order via `dispatch`. The dispatcher walks the
//! per-(scope, mode) trie maintained by `Keymaps`, buffering partial
//! sequences and emitting a match when a complete keymap is recognized.
//!
//! Inputs to each `dispatch` call:
//!   * `keymaps`     — the parsed keymap tries.
//!   * `layers`      — focus stack, bottom-first. Topmost layer = last.
//!   * `editor_mode` — the editor's current Mode (normal / insert / visual).
//!                     A focus layer's `mode_override` can replace this.
//!   * `stroke`      — the keystroke just received.
//!
//! Resolution rules:
//!   * Effective mode = topmost layer's `mode_override`, else `editor_mode`.
//!   * Effective passthrough = topmost layer's `passthrough_printable`.
//!   * If passthrough && stroke is plain printable (no ctrl/alt/super/
//!     hyper/meta and not a named key), `dispatch` returns immediately
//!     with `consumed = false`. This drops any in-flight sequence so the
//!     WebView's `<input>` receives the character cleanly.
//!   * Otherwise the stroke is appended to `pending`. On the FIRST
//!     stroke of a sequence, the dispatcher walks `layers` top-first and
//!     locks `active_scope` to the first scope whose trie has the
//!     pending sequence as a node (terminal or prefix). All subsequent
//!     strokes consult only `active_scope`'s trie.
//!   * Within the active scope's trie, the existing matching strategy
//!     applies: terminal-with-no-children fires immediately;
//!     terminal-with-children remembers `last_valid_len` and waits;
//!     non-matching strokes commit the saved partial (if any) and reset.

const std = @import("std");
const keymapspkg = @import("mod.zig");
const ks = @import("KeyStroke.zig");

const Allocator = std.mem.Allocator;
const Keymaps = keymapspkg.Keymaps;
const Mode = keymapspkg.Mode;
const Scope = keymapspkg.Scope;
const FocusLayer = keymapspkg.FocusLayer;
const KeyStroke = ks.KeyStroke;
const Modifiers = ks.Modifiers;
const named = ks.named;

pub const Dispatcher = @This();

pub const Result = struct {
    /// The matched sequence in canonical text form ("ctrl+t", "g g", ...).
    /// Owned by the caller; free with `alloc.free` once consumed.
    matched: ?[]u8 = null,
    /// True when the dispatcher absorbed this keystroke (caller should not
    /// forward it). False means the key did not participate in any keymap
    /// and should propagate to the WebView.
    consumed: bool = false,
    /// When `matched` is non-null, the scope whose binding fired. Allows
    /// the caller to route the matched sequence to the right listener.
    matched_scope: ?Scope = null,
};

alloc: Allocator,
pending: std.ArrayListUnmanaged(KeyStroke) = .{},
last_valid_len: usize = 0,
active_scope: ?Scope = null,

pub fn init(alloc: Allocator) Dispatcher {
    return .{ .alloc = alloc };
}

pub fn deinit(self: *Dispatcher) void {
    self.pending.deinit(self.alloc);
}

pub fn reset(self: *Dispatcher) void {
    self.pending.clearRetainingCapacity();
    self.last_valid_len = 0;
    self.active_scope = null;
}

pub fn dispatch(
    self: *Dispatcher,
    keymaps: *Keymaps,
    layers: []const FocusLayer,
    editor_mode: Mode,
    raw_stroke: KeyStroke,
) !Result {
    const stroke = normalizeStroke(raw_stroke);
    const effective_mode = effectiveMode(layers, editor_mode);
    const passthrough = layers.len > 0 and layers[layers.len - 1].passthrough_printable;

    if (passthrough and isPlainPrintable(stroke)) {
        // Cancel any half-typed sequence; the user is typing text now.
        self.reset();
        return .{ .consumed = false };
    }

    try self.pending.append(self.alloc, stroke);

    // Lock onto a scope on the first stroke of the sequence by walking
    // the focus stack top-first.
    if (self.active_scope == null) {
        var i: usize = layers.len;
        while (i > 0) {
            i -= 1;
            const layer = layers[i];
            const t = keymaps.trie(layer.scope, effective_mode);
            if (t.get(self.pending.items)) |_| {
                self.active_scope = layer.scope;
                break;
            }
        }

        if (self.active_scope == null) {
            self.reset();
            return .{ .consumed = false };
        }
    }

    const scope = self.active_scope.?;
    const t = keymaps.trie(scope, effective_mode);

    if (t.get(self.pending.items)) |node| {
        const is_terminal = node.values.items.len > 0;
        const can_continue = node.childrens.count() > 0;

        if (is_terminal and !can_continue) {
            const out = try self.formatPending(self.pending.items.len);
            self.reset();
            return .{ .matched = out, .consumed = true, .matched_scope = scope };
        }

        if (is_terminal) {
            self.last_valid_len = self.pending.items.len;
        }
        return .{ .consumed = true };
    }

    // The new stroke broke the chain in the active scope. Commit the
    // previous valid match (if any) under that scope.
    if (self.last_valid_len > 0) {
        const out = try self.formatPending(self.last_valid_len);
        const matched_scope = scope;
        self.reset();
        return .{ .matched = out, .consumed = true, .matched_scope = matched_scope };
    }

    self.reset();
    return .{ .consumed = false };
}

/// Returns true when a partial match is buffered.
pub fn hasPendingMatch(self: *const Dispatcher) bool {
    return self.last_valid_len > 0;
}

/// Commit the buffered partial match, if any, and reset state.
/// Returns the matched sequence + scope, or null if there is nothing
/// to flush. Caller owns the returned `sequence` slice.
pub const FlushResult = struct {
    sequence: []u8,
    scope: Scope,
};

pub fn flushPending(self: *Dispatcher) !?FlushResult {
    if (self.last_valid_len == 0) return null;
    const scope = self.active_scope orelse {
        self.reset();
        return null;
    };
    const out = try self.formatPending(self.last_valid_len);
    self.reset();
    return .{ .sequence = out, .scope = scope };
}

fn effectiveMode(layers: []const FocusLayer, editor_mode: Mode) Mode {
    var i: usize = layers.len;
    while (i > 0) {
        i -= 1;
        if (layers[i].mode_override) |m| return m;
    }
    return editor_mode;
}

fn isPlainPrintable(stroke: KeyStroke) bool {
    if (stroke.mods.ctrl or stroke.mods.alt or stroke.mods.super or
        stroke.mods.hyper or stroke.mods.meta) return false;
    if (codepointName(stroke.codepoint) != null) return false;
    if (stroke.codepoint < 0x20) return false;
    return true;
}

/// Normalize so that "shift+a" and "shift+A" both map to the same stroke.
fn normalizeStroke(stroke: KeyStroke) KeyStroke {
    var s = stroke;
    if (s.codepoint >= 'A' and s.codepoint <= 'Z') {
        s.codepoint = s.codepoint + ('a' - 'A');
    }
    return s;
}

fn formatPending(self: *Dispatcher, len: usize) ![]u8 {
    var buf: std.ArrayListUnmanaged(u8) = .{};
    errdefer buf.deinit(self.alloc);

    for (self.pending.items[0..len], 0..) |stroke, i| {
        if (i > 0) try buf.append(self.alloc, ' ');
        try writeStroke(&buf, self.alloc, stroke);
    }

    return buf.toOwnedSlice(self.alloc);
}

fn writeStroke(buf: *std.ArrayListUnmanaged(u8), alloc: Allocator, stroke: KeyStroke) !void {
    if (stroke.mods.ctrl) try buf.appendSlice(alloc, "ctrl+");
    if (stroke.mods.alt) try buf.appendSlice(alloc, "alt+");
    if (stroke.mods.shift) try buf.appendSlice(alloc, "shift+");
    if (stroke.mods.super) try buf.appendSlice(alloc, "super+");
    if (stroke.mods.hyper) try buf.appendSlice(alloc, "hyper+");
    if (stroke.mods.meta) try buf.appendSlice(alloc, "meta+");

    if (codepointName(stroke.codepoint)) |name| {
        try buf.appendSlice(alloc, name);
        return;
    }

    var utf8: [4]u8 = undefined;
    const n = try std.unicode.utf8Encode(stroke.codepoint, &utf8);
    try buf.appendSlice(alloc, utf8[0..n]);
}

fn codepointName(cp: u21) ?[]const u8 {
    return switch (cp) {
        named.escape => "escape",
        named.enter => "enter",
        named.tab => "tab",
        named.backspace => "backspace",
        named.space => "space",
        named.delete => "delete",
        named.insert => "insert",
        named.home => "home",
        named.end => "end",
        named.page_up => "page_up",
        named.page_down => "page_down",
        named.up => "up",
        named.down => "down",
        named.left => "left",
        named.right => "right",
        named.f1 => "f1",
        named.f2 => "f2",
        named.f3 => "f3",
        named.f4 => "f4",
        named.f5 => "f5",
        named.f6 => "f6",
        named.f7 => "f7",
        named.f8 => "f8",
        named.f9 => "f9",
        named.f10 => "f10",
        named.f11 => "f11",
        named.f12 => "f12",
        else => null,
    };
}

const testing = std.testing;

const editor_only_layers: [2]FocusLayer = .{
    .{ .scope = .global },
    .{ .scope = .editor },
};

test "dispatch fires on terminal with no continuation" {
    const alloc = testing.allocator;
    var keymaps = try Keymaps.init(alloc);
    defer keymaps.deinit();

    try keymaps.insert(.global, .normal, "ctrl+t");

    var disp = Dispatcher.init(alloc);
    defer disp.deinit();

    const res = try disp.dispatch(
        &keymaps,
        &editor_only_layers,
        .normal,
        .{ .codepoint = 't', .mods = .{ .ctrl = true } },
    );
    defer if (res.matched) |m| alloc.free(m);

    try testing.expect(res.consumed);
    try testing.expect(res.matched != null);
    try testing.expectEqualStrings("ctrl+t", res.matched.?);
    try testing.expectEqual(Scope.global, res.matched_scope.?);
}

test "dispatch buffers and prefers longest match" {
    const alloc = testing.allocator;
    var keymaps = try Keymaps.init(alloc);
    defer keymaps.deinit();

    try keymaps.insert(.editor, .normal, "ctrl+l");
    try keymaps.insert(.editor, .normal, "ctrl+l ctrl+v");
    try keymaps.insert(.editor, .normal, "ctrl+l ctrl+v v");

    var disp = Dispatcher.init(alloc);
    defer disp.deinit();

    var r = try disp.dispatch(&keymaps, &editor_only_layers, .normal, .{ .codepoint = 'l', .mods = .{ .ctrl = true } });
    try testing.expect(r.consumed);
    try testing.expect(r.matched == null);

    r = try disp.dispatch(&keymaps, &editor_only_layers, .normal, .{ .codepoint = 'v', .mods = .{ .ctrl = true } });
    try testing.expect(r.consumed);
    try testing.expect(r.matched == null);

    r = try disp.dispatch(&keymaps, &editor_only_layers, .normal, .{ .codepoint = 'v', .mods = .{} });
    defer if (r.matched) |m| alloc.free(m);
    try testing.expect(r.consumed);
    try testing.expectEqualStrings("ctrl+l ctrl+v v", r.matched.?);
    try testing.expectEqual(Scope.editor, r.matched_scope.?);
}

test "dispatch falls back to last valid match when next key breaks the chain" {
    const alloc = testing.allocator;
    var keymaps = try Keymaps.init(alloc);
    defer keymaps.deinit();

    try keymaps.insert(.editor, .normal, "g");
    try keymaps.insert(.editor, .normal, "g g");

    var disp = Dispatcher.init(alloc);
    defer disp.deinit();

    var r = try disp.dispatch(&keymaps, &editor_only_layers, .normal, .{ .codepoint = 'g', .mods = .{} });
    try testing.expect(r.consumed);
    try testing.expect(r.matched == null);

    // 'q' is unmapped. Active scope = editor. Editor has no `g q`, so the
    // saved `g` should fire.
    r = try disp.dispatch(&keymaps, &editor_only_layers, .normal, .{ .codepoint = 'q', .mods = .{} });
    defer if (r.matched) |m| alloc.free(m);
    try testing.expect(r.consumed);
    try testing.expectEqualStrings("g", r.matched.?);
    try testing.expectEqual(Scope.editor, r.matched_scope.?);
}

test "dispatch returns unconsumed when key has no mapping" {
    const alloc = testing.allocator;
    var keymaps = try Keymaps.init(alloc);
    defer keymaps.deinit();

    try keymaps.insert(.editor, .normal, "i");

    var disp = Dispatcher.init(alloc);
    defer disp.deinit();

    const r = try disp.dispatch(&keymaps, &editor_only_layers, .normal, .{ .codepoint = 'q', .mods = .{} });
    try testing.expect(!r.consumed);
    try testing.expect(r.matched == null);
}

test "passthrough drops printable keys without consuming" {
    const alloc = testing.allocator;
    var keymaps = try Keymaps.init(alloc);
    defer keymaps.deinit();

    // Editor below has bindings for `l` but the topmost layer is the
    // command palette with passthrough on. Plain `l` must not be consumed.
    try keymaps.insert(.editor, .normal, "l");
    try keymaps.insert(.command_palette, .normal, "escape");

    const layers = [_]FocusLayer{
        .{ .scope = .global },
        .{ .scope = .editor },
        .{ .scope = .command_palette, .mode_override = .normal, .passthrough_printable = true },
    };

    var disp = Dispatcher.init(alloc);
    defer disp.deinit();

    var r = try disp.dispatch(&keymaps, &layers, .insert, .{ .codepoint = 'l', .mods = .{} });
    try testing.expect(!r.consumed);
    try testing.expect(r.matched == null);

    // Named keys still route through the trie. `escape` is a palette cmd.
    r = try disp.dispatch(&keymaps, &layers, .insert, .{ .codepoint = 0x1b, .mods = .{} });
    defer if (r.matched) |m| alloc.free(m);
    try testing.expect(r.consumed);
    try testing.expectEqualStrings("escape", r.matched.?);
    try testing.expectEqual(Scope.command_palette, r.matched_scope.?);
}

test "topmost layer wins over lower layers for same sequence" {
    const alloc = testing.allocator;
    var keymaps = try Keymaps.init(alloc);
    defer keymaps.deinit();

    try keymaps.insert(.editor, .normal, "tab");
    try keymaps.insert(.command_palette, .normal, "tab");

    const layers = [_]FocusLayer{
        .{ .scope = .global },
        .{ .scope = .editor },
        .{ .scope = .command_palette, .mode_override = .normal, .passthrough_printable = true },
    };

    var disp = Dispatcher.init(alloc);
    defer disp.deinit();

    const r = try disp.dispatch(&keymaps, &layers, .insert, .{ .codepoint = 0x09, .mods = .{} });
    defer if (r.matched) |m| alloc.free(m);
    try testing.expect(r.consumed);
    try testing.expectEqual(Scope.command_palette, r.matched_scope.?);
}

test "global scope wins when no other layer matches" {
    const alloc = testing.allocator;
    var keymaps = try Keymaps.init(alloc);
    defer keymaps.deinit();

    try keymaps.insert(.global, .normal, "super+k");

    const layers = [_]FocusLayer{
        .{ .scope = .global },
        .{ .scope = .editor },
        .{ .scope = .command_palette, .mode_override = .normal, .passthrough_printable = true },
    };

    var disp = Dispatcher.init(alloc);
    defer disp.deinit();

    const r = try disp.dispatch(&keymaps, &layers, .normal, .{ .codepoint = 'k', .mods = .{ .super = true } });
    defer if (r.matched) |m| alloc.free(m);
    try testing.expect(r.consumed);
    try testing.expectEqualStrings("super+k", r.matched.?);
    try testing.expectEqual(Scope.global, r.matched_scope.?);
}
