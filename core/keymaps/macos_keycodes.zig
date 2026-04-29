//! Translate macOS NSEvent virtual keycodes + modifier bitmask
//! (as delivered by the Objective-C key handler bridge) into a `KeyStroke`.
//!
//! The modifier bitmask layout matches `modifierMaskFromEvent` in
//! `electrobun/.../nativeWrapper.mm`:
//!   bit 0 = shift
//!   bit 1 = control
//!   bit 2 = option (alt)
//!   bit 3 = command (super)

const std = @import("std");
const ks = @import("KeyStroke.zig");

pub const KeyStroke = ks.KeyStroke;
pub const Modifiers = ks.Modifiers;
pub const named = ks.named;

/// Map a macOS virtual keycode to a base codepoint (US ANSI layout).
/// Returns null for keys we don't recognize or for pure-modifier keys
/// (shift/ctrl/cmd/option/caps-lock pressed alone).
pub fn keycodeToCodepoint(keycode: u32) ?u21 {
    return switch (keycode) {
        // letters (US ANSI)
        0x00 => 'a',
        0x0B => 'b',
        0x08 => 'c',
        0x02 => 'd',
        0x0E => 'e',
        0x03 => 'f',
        0x05 => 'g',
        0x04 => 'h',
        0x22 => 'i',
        0x26 => 'j',
        0x28 => 'k',
        0x25 => 'l',
        0x2E => 'm',
        0x2D => 'n',
        0x1F => 'o',
        0x23 => 'p',
        0x0C => 'q',
        0x0F => 'r',
        0x01 => 's',
        0x11 => 't',
        0x20 => 'u',
        0x09 => 'v',
        0x0D => 'w',
        0x07 => 'x',
        0x10 => 'y',
        0x06 => 'z',

        // digits
        0x12 => '1',
        0x13 => '2',
        0x14 => '3',
        0x15 => '4',
        0x17 => '5',
        0x16 => '6',
        0x1A => '7',
        0x1C => '8',
        0x19 => '9',
        0x1D => '0',

        // punctuation
        0x1B => '-',
        0x18 => '=',
        0x21 => '[',
        0x1E => ']',
        0x2A => '\\',
        0x29 => ';',
        0x27 => '\'',
        0x2B => ',',
        0x2F => '.',
        0x2C => '/',
        0x32 => '`',

        // named keys
        0x35 => named.escape,
        0x24 => named.enter,
        0x4C => named.enter, // numpad enter
        0x30 => named.tab,
        0x33 => named.backspace,
        0x31 => named.space,
        0x75 => named.delete,
        0x72 => named.insert,
        0x73 => named.home,
        0x77 => named.end,
        0x74 => named.page_up,
        0x79 => named.page_down,
        0x7E => named.up,
        0x7D => named.down,
        0x7B => named.left,
        0x7C => named.right,
        0x7A => named.f1,
        0x78 => named.f2,
        0x63 => named.f3,
        0x76 => named.f4,
        0x60 => named.f5,
        0x61 => named.f6,
        0x62 => named.f7,
        0x64 => named.f8,
        0x65 => named.f9,
        0x6D => named.f10,
        0x67 => named.f11,
        0x6F => named.f12,

        else => null,
    };
}

/// Translate the bridge mask (bit 0=shift, 1=ctrl, 2=alt, 3=super) to
/// `Modifiers`.
pub fn modifiersFromMask(mask: u32) Modifiers {
    return .{
        .shift = (mask & (1 << 0)) != 0,
        .ctrl = (mask & (1 << 1)) != 0,
        .alt = (mask & (1 << 2)) != 0,
        .super = (mask & (1 << 3)) != 0,
    };
}

/// Build a `KeyStroke` from raw NSEvent values. Returns null for keycodes
/// we cannot translate (typically pure-modifier presses).
pub fn keystrokeFromEvent(keycode: u32, modifier_mask: u32) ?KeyStroke {
    const cp = keycodeToCodepoint(keycode) orelse return null;
    return .{
        .codepoint = cp,
        .mods = modifiersFromMask(modifier_mask),
    };
}
