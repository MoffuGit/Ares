const sizepkg = @import("../size.zig");
const inputpkg = @import("../input.zig");

pub const Message = union(enum) {
    buffer_update: u64,
    select_entry: u64,
    resize: sizepkg.Size,
    scroll: u64,
    set_cursor_position: struct {
        row: u64,
        col: u64,
    },
    mouse_button: inputpkg.MouseButtonEvent,
    mouse_move: inputpkg.MouseMoveEvent,
};
