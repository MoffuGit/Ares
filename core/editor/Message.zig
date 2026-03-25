const sizepkg = @import("../size.zig");

pub const Message = union(enum) {
    buffer_update: void,
    select_entry: u64,
    resize: sizepkg.Size,
    scroll: u64,
};
