pub const btree = @import("datastruct/btree.zig");
pub const mpsc = @import("datastruct/mpsc.zig");
pub const multi_mpsc = @import("datastruct/multi_mpsc.zig");
pub const queue = @import("datastruct/queue.zig");
pub const slotmap = @import("datastruct/slotmap.zig");

test {
    _ = multi_mpsc;
    _ = mpsc;
    _ = queue;
    _ = slotmap;
    _ = btree;
}
