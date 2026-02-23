const vaxis = @import("vaxis");
const Action = @import("core").keymaps.Action;

pub const Message = union(enum) {
    scheme: vaxis.Color.Scheme,
};
