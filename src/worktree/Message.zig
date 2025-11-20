const xev = @import("../global.zig").xev;

pub const Message = union(enum) {
    fs_event: xev.FsEvent,
    pwd: []u8,
};
