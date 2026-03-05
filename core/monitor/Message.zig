const Monitor = @import("mod.zig");

pub const Message = union(enum) {
    add: *Monitor.WatchRequest,
    remove: u64,
};
