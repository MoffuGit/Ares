const sizepkg = @import("../size.zig");
const inputpkg = @import("../input.zig");

pub const Message = union(enum) {
    buffer_update: u64,
    select_entry: u64,
    resize: sizepkg.ScreenSize,
    scroll: u64,
    mouse_button: inputpkg.MouseButtonEvent,
    mouse_move: inputpkg.MouseMoveEvent,
};
