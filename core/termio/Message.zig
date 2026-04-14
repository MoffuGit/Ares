const sizepkg = @import("../size.zig");
const inputpkg = @import("../input.zig");

pub const Message = union(enum) {
    resize: sizepkg.Size,
    mouse_button: inputpkg.MouseButtonEvent,
    mouse_move: inputpkg.MouseMoveEvent,
};
