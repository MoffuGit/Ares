const apprt = @import("../apprt/embedded.zig");

pub const Message = union(enum) {
    resize: apprt.SurfaceSize,
};
