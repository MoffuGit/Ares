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
