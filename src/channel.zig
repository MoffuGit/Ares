const std = @import("std");
const Io = std.Io;
const Cancelable = Io.Cancelable;
const QueueClosedError = Io.QueueClosedError;

pub fn SenderType(Elem: type) type {
    return struct {
        channel: *Channel(Elem),

        const Self = @This();

        pub fn close(s: *Self, io: Io) void {
            const prev = s.channel.sender_count.fetchSub(1, .acq_rel);
            if (prev == 1) s.channel.queue.close(io);
            s.* = undefined;
        }

        pub fn clone(s: *Self) Self {
            _ = s.channel.sender_count.fetchAdd(1, .acq_rel);
            return .{ .channel = s.channel };
        }

        /// Appends elements to the end of the queue, potentially blocking if
        /// there is insufficient capacity. Returns when any one of the
        /// following conditions is satisfied:
        ///
        /// * At least `min` elements have been added to the queue
        /// * The queue is closed
        /// * The current task is canceled
        ///
        /// Returns how many of `elements` have been added to the queue, if any.
        /// If an error is returned, no elements have been added.
        ///
        /// If the queue is closed or the task is canceled, but some items were
        /// already added before the closure or cancelation, then `put` may
        /// return a number lower than `min`, in which case future calls are
        /// guaranteed to return `error.Canceled` or `error.Closed`.
        ///
        /// A return value of 0 is only possible if `min` is 0, in which case
        /// the call is guaranteed to queue as many of `elements` as is possible
        /// *without* blocking.
        ///
        /// Asserts that `elements.len >= min`.
        pub fn put(s: *Self, io: Io, elements: []const Elem, min: usize) (QueueClosedError || Cancelable)!usize {
            return s.channel.queue.put(io, elements, min);
        }

        pub fn putAll(s: *Self, io: Io, elements: []const Elem) (QueueClosedError || Cancelable)!void {
            return s.channel.queue.putAll(io, elements);
        }

        pub fn putUncancelable(s: *Self, io: Io, elements: []const Elem, min: usize) QueueClosedError!usize {
            return s.channel.queue.putUncancelable(io, elements, min);
        }

        pub fn putOne(s: *Self, io: Io, item: Elem) (QueueClosedError || Cancelable)!void {
            return s.channel.queue.putOne(io, item);
        }

        pub fn putOneUncancelable(s: *Self, io: Io, item: Elem) QueueClosedError!void {
            return s.channel.queue.putOneUncancelable(io, item);
        }
    };
}

pub fn ReceiverType(Elem: type) type {
    return struct {
        channel: *Channel(Elem),

        const Self = @This();

        pub fn close(r: *Self, io: Io) void {
            const prev = r.channel.receiver_count.fetchSub(1, .acq_rel);
            if (prev == 1) r.channel.queue.close(io);
            r.* = undefined;
        }

        /// Receives elements from the beginning of the queue, potentially blocking
        /// if there are insufficient elements currently in the queue. Returns when
        /// any one of the following conditions is satisfied:
        ///
        /// * At least `min` elements have been received from the queue
        /// * The queue is closed and contains no buffered elements
        /// * The current task is canceled
        ///
        /// Returns how many elements of `buffer` have been populated, if any.
        /// If an error is returned, no elements have been populated.
        ///
        /// If the queue is closed or the task is canceled, but some items were
        /// already received before the closure or cancelation, then `get` may
        /// return a number lower than `min`, in which case future calls are
        /// guaranteed to return `error.Canceled` or `error.Closed`.
        ///
        /// A return value of 0 is only possible if `min` is 0, in which case
        /// the call is guaranteed to fill as much of `buffer` as is possible
        /// *without* blocking.
        ///
        /// Asserts that `buffer.len >= min`.
        pub fn get(r: *Self, io: Io, buffer: []Elem, min: usize) (QueueClosedError || Cancelable)!usize {
            return r.channel.queue.get(io, buffer, min);
        }

        pub fn getUncancelable(r: *Self, io: Io, buffer: []Elem, min: usize) QueueClosedError!usize {
            return r.channel.queue.getUncancelable(io, buffer, min);
        }

        pub fn getOne(r: *Self, io: Io) (QueueClosedError || Cancelable)!Elem {
            return r.channel.queue.getOne(io);
        }

        pub fn getOneUncancelable(r: *Self, io: Io) QueueClosedError!Elem {
            return r.channel.queue.getOneUncancelable(io);
        }
    };
}

pub fn Channel(Elem: type) type {
    return struct {
        queue: Io.Queue(Elem),
        sender_count: std.atomic.Value(u64),
        receiver_count: std.atomic.Value(u64),

        const Self = @This();
        pub const Sender = SenderType(Elem);
        pub const Receiver = ReceiverType(Elem);

        pub fn init(buffer: []Elem) Self {
            return .{
                .queue = .init(buffer),
                .sender_count = .init(0),
                .receiver_count = .init(0),
            };
        }

        pub fn sender(c: *Self) Sender {
            _ = c.sender_count.fetchAdd(1, .acq_rel);
            return .{ .channel = c };
        }

        pub fn receiver(c: *Self) Receiver {
            _ = c.receiver_count.fetchAdd(1, .acq_rel);
            return .{ .channel = c };
        }

        pub fn close(c: *Self, io: Io) void {
            c.queue.close(io);
        }

        pub fn closed(c: *Self, io: Io) !bool {
            try c.queue.type_erased.mutex.lock(io);
            defer c.queue.type_erased.mutex.unlock(io);

            return c.queue.type_erased.closed;
        }
    };
}
