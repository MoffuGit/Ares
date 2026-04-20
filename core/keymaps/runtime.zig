const std = @import("std");
const builtin = @import("builtin");
const global = @import("../global.zig");
const Settings = @import("../settings/mod.zig");
const keymapspkg = @import("mod.zig");
const keystrokepkg = @import("KeyStroke.zig");

const KeyStroke = keystrokepkg.KeyStroke;
const Modifiers = keystrokepkg.Modifiers;
const named = keystrokepkg.named;
const KeymapEntry = keymapspkg.KeymapEntry;

const sequence_timeout_ms: i64 = 500;

const TerminalMatch = struct {
    sequence: []const u8,
    action: []const u8,
};

const MatchResult = struct {
    terminal: ?TerminalMatch = null,
    has_prefix: bool = false,
    has_children: bool = false,
};

pub const Runtime = struct {
    alloc: std.mem.Allocator,
    mode: keymapspkg.Mode = .normal,
    observed_generation: u64 = 0,
    last_input_ms: i64 = 0,
    sequence: std.ArrayListUnmanaged(KeyStroke) = .{},
    last_terminal: ?TerminalMatch = null,

    pub fn init(alloc: std.mem.Allocator) Runtime {
        return .{ .alloc = alloc };
    }

    pub fn deinit(self: *Runtime) void {
        self.sequence.deinit(self.alloc);
    }

    pub fn handleKeyDown(self: *Runtime, settings: *Settings, key_code: u32, native_modifiers: u32, is_repeat: bool) bool {
        _ = is_repeat;

        if (!settings.keymaps_initialized) return false;
        self.syncGeneration(settings.keymap_generation);

        const now = std.time.milliTimestamp();
        if (self.sequence.items.len > 0 and now - self.last_input_ms > sequence_timeout_ms) {
            if (self.last_terminal) |terminal| {
                self.dispatchMatch(terminal);
            }
            self.reset();
        }

        const stroke = nativeKeyStroke(key_code, native_modifiers) orelse return false;
        return self.processStroke(settings, stroke, now, true);
    }

    fn processStroke(self: *Runtime, settings: *Settings, stroke: KeyStroke, now: i64, allow_retry: bool) bool {
        self.sequence.append(self.alloc, stroke) catch {
            self.reset();
            return false;
        };

        const match = evaluate(self.sequence.items, settings.keymaps.entries(.global, self.mode));
        if (!match.has_prefix) {
            const pending = self.last_terminal;
            self.reset();

            if (pending) |terminal| {
                self.dispatchMatch(terminal);
                if (allow_retry) {
                    return self.processStroke(settings, stroke, now, false);
                }
                return true;
            }

            if (allow_retry) {
                return self.processStroke(settings, stroke, now, false);
            }

            return false;
        }

        self.last_input_ms = now;

        if (match.terminal) |terminal| {
            if (!match.has_children) {
                self.reset();
                self.dispatchMatch(terminal);
                return true;
            }

            self.last_terminal = terminal;
            return true;
        }

        self.last_terminal = null;
        return true;
    }

    fn syncGeneration(self: *Runtime, generation: u64) void {
        if (self.observed_generation == generation) return;
        self.observed_generation = generation;
        self.reset();
    }

    fn reset(self: *Runtime) void {
        self.sequence.clearRetainingCapacity();
        self.last_terminal = null;
        self.last_input_ms = 0;
    }

    fn dispatchMatch(self: *Runtime, terminal: TerminalMatch) void {
        self.applyAction(terminal.action);

        const owned_sequence = self.alloc.dupe(u8, terminal.sequence) catch return;
        errdefer self.alloc.free(owned_sequence);

        const owned_action = self.alloc.dupe(u8, terminal.action) catch {
            self.alloc.free(owned_sequence);
            return;
        };
        errdefer self.alloc.free(owned_action);

        if (global.state.emit(.{ .keymapMatch = .{
            .sequence = owned_sequence,
            .action = owned_action,
        } }, .instant) == 0) {
            self.alloc.free(owned_sequence);
            self.alloc.free(owned_action);
        }
    }

    fn applyAction(self: *Runtime, action: []const u8) void {
        if (std.mem.eql(u8, action, "workspace:enter_insert")) {
            self.setMode(.insert);
            return;
        }
        if (std.mem.eql(u8, action, "workspace:enter_visual")) {
            self.setMode(.visual);
            return;
        }
        if (std.mem.eql(u8, action, "workspace:enter_normal")) {
            self.setMode(.normal);
        }
    }

    fn setMode(self: *Runtime, mode: keymapspkg.Mode) void {
        if (self.mode == mode) return;

        self.mode = mode;
        self.reset();
        _ = global.state.emit(.{ .modeUpdate = .{ .mode = @intFromEnum(mode) } }, .instant);
    }
};

fn evaluate(sequence: []const KeyStroke, entries: []const KeymapEntry) MatchResult {
    var result: MatchResult = .{};

    for (entries) |entry| {
        if (!isPrefix(sequence, entry.strokes)) continue;

        result.has_prefix = true;
        if (sequence.len == entry.strokes.len) {
            result.terminal = .{ .sequence = entry.sequence, .action = entry.action };
        } else {
            result.has_children = true;
        }
    }

    return result;
}

fn isPrefix(prefix: []const KeyStroke, candidate: []const KeyStroke) bool {
    if (prefix.len > candidate.len) return false;

    for (prefix, candidate[0..prefix.len]) |lhs, rhs| {
        if (!KeyStroke.eql(lhs, rhs)) return false;
    }

    return true;
}

fn nativeKeyStroke(key_code: u32, native_modifiers: u32) ?KeyStroke {
    const codepoint = switch (builtin.os.tag) {
        .macos => macosKeyCodeToCodepoint(key_code),
        .windows => windowsKeyCodeToCodepoint(key_code),
        else => null,
    } orelse return null;

    return .{
        .codepoint = codepoint,
        .mods = normalizeModifiers(native_modifiers),
    };
}

// Electrobun window key events use native modifier bits:
// shift=0, ctrl=1, alt=2, super=3. Ares keymaps store alt=1 and ctrl=2.
fn normalizeModifiers(native_modifiers: u32) Modifiers {
    return .{
        .shift = native_modifiers & (1 << 0) != 0,
        .alt = native_modifiers & (1 << 2) != 0,
        .ctrl = native_modifiers & (1 << 1) != 0,
        .super = native_modifiers & (1 << 3) != 0,
    };
}

fn macosKeyCodeToCodepoint(key_code: u32) ?u21 {
    return switch (key_code) {
        0 => 'a',
        1 => 's',
        2 => 'd',
        3 => 'f',
        4 => 'h',
        5 => 'g',
        6 => 'z',
        7 => 'x',
        8 => 'c',
        9 => 'v',
        11 => 'b',
        12 => 'q',
        13 => 'w',
        14 => 'e',
        15 => 'r',
        16 => 'y',
        17 => 't',
        18 => '1',
        19 => '2',
        20 => '3',
        21 => '4',
        22 => '6',
        23 => '5',
        24 => '=',
        25 => '9',
        26 => '7',
        27 => '-',
        28 => '8',
        29 => '0',
        30 => ']',
        31 => 'o',
        32 => 'u',
        33 => '[',
        34 => 'i',
        35 => 'p',
        37 => 'l',
        38 => 'j',
        39 => '\'',
        40 => 'k',
        41 => ';',
        42 => '\\',
        43 => ',',
        44 => '/',
        45 => 'n',
        46 => 'm',
        47 => '.',
        48 => named.tab,
        49 => named.space,
        50 => '`',
        51 => named.backspace,
        53 => named.escape,
        96 => named.f5,
        97 => named.f6,
        98 => named.f7,
        99 => named.f3,
        100 => named.f8,
        101 => named.f9,
        103 => named.f11,
        109 => named.f10,
        111 => named.f12,
        114 => named.insert,
        115 => named.home,
        116 => named.page_up,
        117 => named.delete,
        118 => named.f4,
        119 => named.end,
        120 => named.f2,
        121 => named.page_down,
        122 => named.f1,
        123 => named.left,
        124 => named.right,
        125 => named.down,
        126 => named.up,
        else => null,
    };
}

fn windowsKeyCodeToCodepoint(key_code: u32) ?u21 {
    if (key_code >= 'A' and key_code <= 'Z') {
        return @intCast(key_code + ('a' - 'A'));
    }
    if (key_code >= '0' and key_code <= '9') {
        return @intCast(key_code);
    }

    return switch (key_code) {
        0x08 => named.backspace,
        0x09 => named.tab,
        0x0D => named.enter,
        0x1B => named.escape,
        0x20 => named.space,
        0x21 => named.page_up,
        0x22 => named.page_down,
        0x23 => named.end,
        0x24 => named.home,
        0x25 => named.left,
        0x26 => named.up,
        0x27 => named.right,
        0x28 => named.down,
        0x2D => named.insert,
        0x2E => named.delete,
        0x70 => named.f1,
        0x71 => named.f2,
        0x72 => named.f3,
        0x73 => named.f4,
        0x74 => named.f5,
        0x75 => named.f6,
        0x76 => named.f7,
        0x77 => named.f8,
        0x78 => named.f9,
        0x79 => named.f10,
        0x7A => named.f11,
        0x7B => named.f12,
        0xBA => ';',
        0xBB => '=',
        0xBC => ',',
        0xBD => '-',
        0xBE => '.',
        0xBF => '/',
        0xC0 => '`',
        0xDB => '[',
        0xDC => '\\',
        0xDD => ']',
        0xDE => '\'',
        else => null,
    };
}
