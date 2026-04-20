const std = @import("std");
const Modifiers = @import("keymaps/KeyStroke.zig").Modifiers;

pub const MouseButton = enum(u8) {
    left = 0,
    middle = 1,
    right = 2,
};

pub const MouseAction = enum(u8) {
    press = 0,
    release = 1,
};

pub const MouseButtonEvent = struct {
    button: MouseButton,
    action: MouseAction,
    x: f64,
    y: f64,
    mods: Modifiers,
};

pub const MouseMoveEvent = struct {
    x: f64,
    y: f64,
    mods: Modifiers,
};

pub const KeyInput = union(enum) {
    text: u21,
    backspace: void,
    delete: void,
    enter: void,
    tab: void,
};

pub const KeyEvent = struct {
    input: KeyInput,
    mods: Modifiers,
    repeat: bool,
};

pub fn parseDomKeyEvent(key: []const u8, mods: Modifiers, repeat: bool) ?KeyEvent {
    const input: KeyInput = if (std.mem.eql(u8, key, "Backspace"))
        .backspace
    else if (std.mem.eql(u8, key, "Delete"))
        .delete
    else if (std.mem.eql(u8, key, "Enter"))
        .enter
    else if (std.mem.eql(u8, key, "Tab"))
        .tab
    else blk: {
        const view = std.unicode.Utf8View.init(key) catch return null;
        var it = view.iterator();
        const cp = it.nextCodepoint() orelse return null;
        if (it.nextCodepoint() != null) return null;
        break :blk .{ .text = cp };
    };

    return .{
        .input = input,
        .mods = mods,
        .repeat = repeat,
    };
}
