//! Stateful keymap dispatcher.
//!
//! Feed it `KeyStroke`s in order via `dispatch`. The dispatcher walks the
//! per-mode trie maintained by `Keymaps`, buffering partial sequences and
//! emitting a match when a complete keymap is recognized.
//!
//! Matching strategy (no timer):
//!   * If the current pending sequence reaches a terminal node and the trie
//!     CAN continue past it, we remember it as the "last valid match" and
//!     keep buffering, hoping for a longer match.
//!   * If we land on a terminal node with no continuation, fire immediately.
//!   * If the next keystroke does not extend the pending prefix, fire the
//!     last valid match (if any) and reset.
//!   * If nothing matches, reset and report the key as unconsumed so the
//!     caller can fall back to other handling.

const std = @import("std");
const keymapspkg = @import("mod.zig");
const ks = @import("KeyStroke.zig");

const Allocator = std.mem.Allocator;
const Keymaps = keymapspkg.Keymaps;
const Mode = keymapspkg.Mode;
const KeyStroke = ks.KeyStroke;
const Modifiers = ks.Modifiers;
const named = ks.named;

pub const Dispatcher = @This();

pub const Result = struct {
    /// The matched sequence in canonical text form ("ctrl+t", "g g", ...).
    /// Owned by the caller; free with `alloc.free` once consumed.
    matched: ?[]u8 = null,
    /// True when the dispatcher absorbed this keystroke (caller should not
    /// forward it). False means the key did not participate in any keymap.
    consumed: bool = false,
};

alloc: Allocator,
mode: Mode = .normal,
pending: std.ArrayListUnmanaged(KeyStroke) = .{},
last_valid_len: usize = 0,

pub fn init(alloc: Allocator) Dispatcher {
    return .{ .alloc = alloc };
}

pub fn deinit(self: *Dispatcher) void {
    self.pending.deinit(self.alloc);
}

pub fn setMode(self: *Dispatcher, mode: Mode) void {
    self.reset();
    self.mode = mode;
}

pub fn reset(self: *Dispatcher) void {
    self.pending.clearRetainingCapacity();
    self.last_valid_len = 0;
}

pub fn dispatch(self: *Dispatcher, keymaps: *Keymaps, raw_stroke: KeyStroke) !Result {
    const stroke = normalizeStroke(raw_stroke);

    try self.pending.append(self.alloc, stroke);

    const trie = keymaps.trie(self.mode);
    if (trie.get(self.pending.items)) |node| {
        const is_terminal = node.values.items.len > 0;
        const can_continue = node.childrens.count() > 0;

        if (is_terminal and !can_continue) {
            const out = try self.formatPending(self.pending.items.len);
            self.reset();
            return .{ .matched = out, .consumed = true };
        }

        if (is_terminal) {
            self.last_valid_len = self.pending.items.len;
        }
        return .{ .consumed = true };
    }

    // No path continues from here. Commit the previous valid match if any.
    if (self.last_valid_len > 0) {
        const out = try self.formatPending(self.last_valid_len);
        self.reset();
        return .{ .matched = out, .consumed = true };
    }

    self.reset();
    return .{ .consumed = false };
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
/// Returns true when a partial match is buffered (a sequence that is a
/// valid keymap, but the trie can still continue and we are waiting to
/// see if the user types a longer match).
pub fn hasPendingMatch(self: *const Dispatcher) bool {
    return self.last_valid_len > 0;
}

/// Commit the buffered partial match, if any, and reset state.
/// Returns the matched sequence as a freshly-allocated string (caller
/// owns) or null if there is nothing to flush.
pub fn flushPending(self: *Dispatcher) !?[]u8 {
    if (self.last_valid_len == 0) return null;
    const out = try self.formatPending(self.last_valid_len);
    self.reset();
    return out;
}

const testing = std.testing;

test "dispatch fires on terminal with no continuation" {
    const alloc = testing.allocator;
    var keymaps = try Keymaps.init(alloc);
    defer keymaps.deinit();

    try keymaps.insert(.normal, "ctrl+t");

    var disp = Dispatcher.init(alloc);
    defer disp.deinit();

    const res = try disp.dispatch(&keymaps, .{ .codepoint = 't', .mods = .{ .ctrl = true } });
    defer if (res.matched) |m| alloc.free(m);

    try testing.expect(res.consumed);
    try testing.expect(res.matched != null);
    try testing.expectEqualStrings("ctrl+t", res.matched.?);
}

test "dispatch buffers and prefers longest match" {
    const alloc = testing.allocator;
    var keymaps = try Keymaps.init(alloc);
    defer keymaps.deinit();

    try keymaps.insert(.normal, "ctrl+l");
    try keymaps.insert(.normal, "ctrl+l ctrl+v");
    try keymaps.insert(.normal, "ctrl+l ctrl+v v");

    var disp = Dispatcher.init(alloc);
    defer disp.deinit();

    // ctrl+l: terminal but trie continues -> wait
    var r = try disp.dispatch(&keymaps, .{ .codepoint = 'l', .mods = .{ .ctrl = true } });
    try testing.expect(r.consumed);
    try testing.expect(r.matched == null);

    // ctrl+v: terminal but trie continues -> wait
    r = try disp.dispatch(&keymaps, .{ .codepoint = 'v', .mods = .{ .ctrl = true } });
    try testing.expect(r.consumed);
    try testing.expect(r.matched == null);

    // v: terminal and trie no longer continues -> fire
    r = try disp.dispatch(&keymaps, .{ .codepoint = 'v', .mods = .{} });
    defer if (r.matched) |m| alloc.free(m);
    try testing.expect(r.consumed);
    try testing.expectEqualStrings("ctrl+l ctrl+v v", r.matched.?);
}

test "dispatch falls back to last valid match when next key breaks the chain" {
    const alloc = testing.allocator;
    var keymaps = try Keymaps.init(alloc);
    defer keymaps.deinit();

    try keymaps.insert(.normal, "g");
    try keymaps.insert(.normal, "g g");

    var disp = Dispatcher.init(alloc);
    defer disp.deinit();

    var r = try disp.dispatch(&keymaps, .{ .codepoint = 'g', .mods = .{} });
    try testing.expect(r.consumed);
    try testing.expect(r.matched == null);

    // 'q' is unmapped. The dispatcher should commit the prior valid "g".
    r = try disp.dispatch(&keymaps, .{ .codepoint = 'q', .mods = .{} });
    defer if (r.matched) |m| alloc.free(m);
    try testing.expect(r.consumed);
    try testing.expectEqualStrings("g", r.matched.?);
}

test "dispatch returns unconsumed when key has no mapping" {
    const alloc = testing.allocator;
    var keymaps = try Keymaps.init(alloc);
    defer keymaps.deinit();

    try keymaps.insert(.normal, "i");

    var disp = Dispatcher.init(alloc);
    defer disp.deinit();

    const r = try disp.dispatch(&keymaps, .{ .codepoint = 'q', .mods = .{} });
    try testing.expect(!r.consumed);
    try testing.expect(r.matched == null);
}
