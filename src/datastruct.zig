pub const btree = @import("datastruct/btree.zig");
pub const slotmap = @import("datastruct/slotmap.zig");
pub const queue = @import("datastruct/queue.zig");
pub const mpsc = @import("datastruct/mpsc.zig");

test {
    _ = mpsc;
    _ = queue;
    _ = slotmap;
    _ = btree;
}
