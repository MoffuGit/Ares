pub const btree = @import("datastruct/btree.zig");
pub const mpsc = @import("datastruct/mpsc.zig");
pub const multi_mpsc = @import("datastruct/multi_mpsc.zig");
pub const multi_queue = @import("datastruct/multi_queue.zig");
pub const queue = @import("datastruct/queue.zig");
pub const slotmap = @import("datastruct/slotmap.zig");
pub const heap = @import("datastruct/heap.zig");
pub const stealing = @import("datastruct/stealing_queue.zig");
pub const doubly_linked_list = @import("datastruct/doubly_linked_list.zig");

test {
    _ = doubly_linked_list;
    _ = heap;
    _ = multi_mpsc;
    _ = multi_queue;
    _ = mpsc;
    _ = queue;
    _ = slotmap;
    _ = btree;
}
