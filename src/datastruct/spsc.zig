// Source: https://github.com/rigtorp/SPSCQueue/tree/master
// License; [SPSCQueue]
const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const atomic = std.atomic;
const math = std.math;
const testing = std.testing;
const Io = std.Io;

pub fn SpscBounded(T: type) type {
    return struct {
        const Self = @This();
        const Padding = (atomic.cache_line - 1) / @sizeOf(T) + 1;

        mask: u16,
        len: u16,
        slots: []T,
        producer: atomic.Value(u16) align(atomic.cache_line),
        cache_consumer: u16,

        consumer: atomic.Value(u16) align(atomic.cache_line),
        cache_producer: u16,

        pub fn init(cap: u16, allocator: Allocator) !Self {
            assert(@sizeOf(T) > 0);

            const _capacity = try math.ceilPowerOfTwo(u16, cap);
            const mask: u16 = @intCast(_capacity - 1);

            const slots = try allocator.alloc(T, _capacity + 2 * Padding);

            return .{
                .len = _capacity,
                .mask = mask,
                .slots = slots,
                .consumer = .init(0),
                .cache_consumer = 0,
                .producer = .init(0),
                .cache_producer = 0,
            };
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            allocator.free(self.slots);
        }

        pub fn capacity(self: *const Self) u16 {
            return self.len;
        }

        pub fn push(self: *Self, value: T) void {
            const write = self.producer.load(.monotonic);
            while (write - self.cache_consumer == self.len) {
                self.cache_consumer = self.consumer.load(.acquire);
                atomic.spinLoopHint();
            }
            self.slot(write).* = value;
            self.producer.store(write +% 1, .release);
        }

        pub fn tryPush(self: *Self, value: T) bool {
            const write = self.producer.load(.monotonic);
            if (write - self.cache_consumer == self.len) {
                self.cache_consumer = self.consumer.load(.acquire);
                if (write - self.cache_consumer == self.len) return false;
            }
            self.slot(write).* = value;
            self.producer.store(write +% 1, .release);
            return true;
        }

        pub fn front(self: *Self) ?*T {
            const read = self.consumer.load(.monotonic);

            if (read == self.cache_producer) {
                self.cache_producer = self.producer.load(.acquire);
                if (read == self.cache_producer) return null;
            }

            return self.slot(read);
        }

        pub fn pop(self: *Self) void {
            const read = self.consumer.load(.monotonic);
            if (self.producer.load(.acquire) == read) unreachable;
            self.consumer.store(read +% 1, .release);
        }

        inline fn slot(self: *Self, index: u16) *T {
            return &self.slots[(index & self.mask) + Padding];
        }
    };
}

test "SPSC bounded pads both ends of its slots allocation" {
    const Queue = SpscBounded(u64);
    var queue = try Queue.init(10, testing.allocator);
    defer queue.deinit(testing.allocator);

    try testing.expectEqual(@as(u16, 16), queue.capacity());
    try testing.expectEqual(@as(usize, 16 + 2 * Queue.Padding), queue.slots.len);
    try testing.expectEqual(&queue.slots[Queue.Padding], queue.slot(0));
    try testing.expectEqual(&queue.slots[Queue.Padding + 15], queue.slot(15));

    for (0..queue.len) |b| {
        queue.push(b);
    }

    try testing.expectEqual(false, queue.tryPush(11));

    for (0..queue.len) |b| {
        const expected: u64 = @intCast(b);
        try testing.expectEqual(queue.front().?.*, expected);
        queue.pop();
    }
}
