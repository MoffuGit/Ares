// Source: https://github.com/rigtorp/SPSCQueue/tree/master
// License; [SPSCQueue]
const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const atomic = std.atomic;
const math = std.math;

pub fn SPSCBounded(T: type) type {
    return struct {
        const Self = @This();
        const Padding = (atomic.cache_line - 1) / @sizeOf(T) + 1;

        mask: u16,
        buffer: []T,
        producer: atomic.Value(u16) align(atomic.cache_line),
        consumer: atomic.Value(u16) align(atomic.cache_line),

        pub fn init(cap: u16, allocator: Allocator) !Self {
            assert(@sizeOf(T) > 0);

            const required_slots = @as(u32, @max(cap, 1)) + 1;
            const ring_capacity = try math.ceilPowerOfTwo(u32, required_slots);
            const mask: u16 = @intCast(ring_capacity - 1);

            const buffer = try allocator.alloc(T, ring_capacity + 2 * Padding);

            return .{
                .mask = mask,
                .buffer = buffer,
                .consumer = .init(0),
                .producer = .init(0),
            };
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            allocator.free(self.buffer);
        }

        pub fn capacity(self: *const Self) u16 {
            return self.mask;
        }

        /// Attempts to append a value, returning false immediately when full.
        /// This must only be called by the queue's single producer.
        pub fn push(self: *Self, value: T) bool {
            const write_index = self.producer.load(.monotonic);
            const next_write_index = self.nextIndex(write_index);

            if (next_write_index == self.consumer.load(.acquire)) return false;

            self.slot(write_index).* = value;
            self.producer.store(next_write_index, .release);
            return true;
        }

        /// Removes and returns a value, or null immediately when empty.
        /// This must only be called by the queue's single consumer.
        pub fn pop(self: *Self) ?T {
            const read_index = self.consumer.load(.monotonic);
            if (read_index == self.producer.load(.acquire)) return null;

            const value = self.slot(read_index).*;
            self.consumer.store(self.nextIndex(read_index), .release);
            return value;
        }

        fn slot(self: *Self, index: u16) *T {
            assert(index <= self.mask);
            return &self.buffer[index + Padding];
        }

        fn nextIndex(self: *const Self, index: u16) u16 {
            return (index +% 1) & self.mask;
        }
    };
}

test "SPSC bounded pads both ends of its slots allocation" {
    const Queue = SPSCBounded(u64);
    var queue = try Queue.init(10, std.testing.allocator);
    defer queue.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u16, 15), queue.capacity());
    try std.testing.expectEqual(@as(usize, 16 + 2 * Queue.Padding), queue.buffer.len);
    try std.testing.expectEqual(&queue.buffer[Queue.Padding], queue.slot(0));
    try std.testing.expectEqual(&queue.buffer[Queue.Padding + 15], queue.slot(15));
    try std.testing.expectEqual(@as(u16, 10), queue.nextIndex(9));
    try std.testing.expectEqual(@as(u16, 0), queue.nextIndex(15));
}

test "SPSC bounded supports its full u16 capacity without overflow" {
    const Queue = SPSCBounded(u8);
    var queue = try Queue.init(math.maxInt(u16), std.testing.allocator);
    defer queue.deinit(std.testing.allocator);

    try std.testing.expectEqual(
        @as(u16, math.maxInt(u16)),
        queue.capacity(),
    );
    try std.testing.expectEqual(
        @as(usize, 65536 + 2 * Queue.Padding),
        queue.buffer.len,
    );
    try std.testing.expectEqual(@as(u16, 0), queue.nextIndex(math.maxInt(u16)));
}

test "SPSC bounded push and pop return immediately when full or empty" {
    const Queue = SPSCBounded(u32);
    var queue = try Queue.init(3, std.testing.allocator);
    defer queue.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?u32, null), queue.pop());

    try std.testing.expect(queue.push(1));
    try std.testing.expect(queue.push(2));
    try std.testing.expect(queue.push(3));
    try std.testing.expect(!queue.push(4));

    try std.testing.expectEqual(@as(?u32, 1), queue.pop());
    try std.testing.expect(queue.push(4));
    try std.testing.expectEqual(@as(?u32, 2), queue.pop());
    try std.testing.expectEqual(@as(?u32, 3), queue.pop());
    try std.testing.expectEqual(@as(?u32, 4), queue.pop());
    try std.testing.expectEqual(@as(?u32, null), queue.pop());
}
