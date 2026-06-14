pub const btree = @import("datastruct/btree.zig");
pub const slotmap = @import("datastruct/slotmap.zig");
pub const queue = @import("datastruct/queue.zig");

test {
    _ = queue;
    _ = slotmap;
    _ = btree;
}
