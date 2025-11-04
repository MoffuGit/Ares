const sizepkg = @import("../size.zig");

pub const Message = union(enum) { size: sizepkg.Size };
