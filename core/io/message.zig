const Io = @import("mod.zig");

pub const Message = union(enum) {
    read: *Io.ReadRequest,
};
