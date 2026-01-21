const vaxis = @import("vaxis");

pub const Event = union(enum) {
    key_press: vaxis.Key,
    key_release: vaxis.Key,
    focus,
    blur,
};
