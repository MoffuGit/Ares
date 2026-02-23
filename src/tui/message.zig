const vaxis = @import("vaxis");

pub const Message = union(enum) {
    scheme: vaxis.Color.Scheme,
};
