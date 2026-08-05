pub const btree = @import("datastruct/btree.zig");
pub const doubly_linked_list = @import("datastruct/doubly_linked_list.zig");
pub const DoublyLinkedList = doubly_linked_list.DoublyLinkedList;
pub const heap = @import("datastruct/heap.zig");
pub const linked_list = @import("datastruct/linked_list.zig");
pub const LinkedList = linked_list.SinglyLinkedList;
pub const mem_map = @import("datastruct/memory_map.zig");
pub const mpsc = @import("datastruct/mpsc.zig");
pub const Mpsc = mpsc.Mpsc;
pub const MpscBounded = mpsc.MpscBounded;
pub const multi_mpsc = @import("datastruct/multi_mpsc.zig");
pub const MultiMpsc = multi_mpsc.MultiMpsc;
pub const multi_queue = @import("datastruct/multi_queue.zig");
pub const MultiQueue = multi_queue.MultiQueue;
pub const queue = @import("datastruct/queue.zig");
pub const Queue = queue.Queue;
pub const slotmap = @import("datastruct/slotmap.zig");
pub const spsc = @import("datastruct/spsc.zig");
pub const SpscBounded = spsc.SpscBounded;
pub const mpmc = @import("datastruct/mpmc.zig");
pub const Mpmc = mpmc.Mpmc;

test {
    _ = mpmc;
    _ = mem_map;
    _ = linked_list;
    _ = doubly_linked_list;
    _ = heap;
    _ = multi_mpsc;
    _ = multi_queue;
    _ = mpsc;
    _ = queue;
    _ = spsc;
    _ = slotmap;
    _ = btree;
}
