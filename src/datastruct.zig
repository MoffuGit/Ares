pub const btree = @import("datastruct/btree.zig");
pub const dequeue = @import("datastruct/dequeue.zig");
pub const Dequeue = dequeue.Dequeue;
pub const doubly_linked_list = @import("datastruct/doubly_linked_list.zig");
pub const DoublyLinkedList = doubly_linked_list.DoublyLinkedList;
pub const heap = @import("datastruct/heap.zig");
pub const linked_list = @import("datastruct/linked_list.zig");
pub const SinglyLinkedList = linked_list.SinglyLinkedList;
pub const mem_map = @import("datastruct/memory_map.zig");
pub const mpsc = @import("datastruct/mpsc.zig");
pub const MpscBounded = mpsc.MpscBounded;
pub const multi_queue = @import("datastruct/multi_queue.zig");
pub const MultiQueue = multi_queue.MultiQueue;
pub const slotmap = @import("datastruct/slotmap.zig");
pub const spsc = @import("datastruct/spsc.zig");
pub const SpscBounded = spsc.SpscBounded;

test {
    _ = mpsc;
    _ = spsc;
    _ = dequeue;
    _ = mem_map;
    _ = linked_list;
    _ = doubly_linked_list;
    _ = heap;
    _ = multi_queue;
    _ = slotmap;
    _ = btree;
}
