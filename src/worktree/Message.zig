const xev = @import("../global.zig").xev;

pub const Message = union(enum) {
    fsevent: u32,
    pwd: []u8,
};
