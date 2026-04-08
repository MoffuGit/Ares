const sizepkg = @import("../size.zig");

pub const Message = union(enum) {
    resize: sizepkg.ScreenSize,
    visible: bool,
    themeUpdate: void,
};
