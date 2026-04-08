const sizepkg = @import("../size.zig");

pub const Message = union(enum) {
    buffer_update: u64,
    select_entry: u64,
    resize: sizepkg.ScreenSize,
    scroll: u64,
};
