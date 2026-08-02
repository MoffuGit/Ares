const std = @import("std");
const Allocator = std.mem.Allocator;
const debug = std.debug;
const assert = debug.assert;
const panic = debug.panic;

const ChunkAllocator = @import("chunk_pool.zig").ChunkAllocator;
const constants = @import("constants.zig");
const MAX_ALIGN = constants.MAX_ALIGN;
const MAX_SIZE = constants.MAX_SIZE;
const datastruct = @import("datastruct.zig");
const btree = datastruct.btree;

pub fn Subscriptions(
    Key: type,
    Args: type,
    comptime comp: *const fn (Key, Key) std.math.Order,
) type {
    return struct {
        const Self = @This();

        const Callback = *const fn (Subscriber, Args) bool;

        const Order = struct {
            fn order(a: u32, b: u32) std.math.Order {
                return std.math.order(a, b);
            }
        };

        const Subscribers = btree.BPlusTree(
            Key,
            ?btree.BPlusTree(u32, Subscriber, Order.order),
            comp,
        );

        pub const Subscriber = struct {
            active: bool,
            callback: Callback,
            context: *anyopaque,
        };

        pub const Dropped = struct {
            key: Key,
            id: u32,
            pub fn order(a: Dropped, b: Dropped) std.math.Order {
                return switch (comp(a.key, b.key)) {
                    .eq => std.math.order(a.id, b.id),
                    else => |ord| ord,
                };
            }
        };

        pub const Subscription = struct {
            subscriptions: *Self,
            key: Key,
            id: u32,

            pub fn enable(self: *const Subscription) void {
                self.subscriptions.enable(self);
            }

            pub fn notify(self: *const Subscription, args: Args) bool {
                return self.subscriptions.notify(self, args);
            }

            pub fn unsubscribe(self: *const Subscription) !void {
                try self.subscriptions.unsubscribe(self);
            }

            pub fn unsubscribeApp(self: *const Subscription) !void {
                try self.subscriptions.unsubscribe(self);
            }
        };

        subscribers: Subscribers,
        dropped: btree.BPlusSet(Dropped, Dropped.order),
        chunk: Allocator,
        next_id: u32,

        const SubscriberTree = btree.BPlusTree(u32, Subscriber, Order.order);
        pub const NODE_SIZE = @max(Subscribers.NODE_SIZE, SubscriberTree.NODE_SIZE, btree.BPlusSet(Dropped, Dropped.order).NODE_SIZE);

        pub fn init(self: *Self, chunk: Allocator) !void {
            self.* = .{
                .next_id = 0,
                .chunk = chunk,
                .subscribers = undefined,
                .dropped = undefined,
            };

            try self.subscribers.init(chunk);
            errdefer self.subscribers.deinit(chunk);

            try self.dropped.init(chunk);
            errdefer self.dropped.deinit(chunk);
        }

        pub fn deinit(self: *Self) void {
            var outer = self.subscribers.iter();
            while (outer.next()) |entry| {
                if (self.subscribers.get_ref(entry.key)) |maybe_subscribers| {
                    if (maybe_subscribers.*) |*subscribers| {
                        self.destroyContexts(subscribers);
                        subscribers.deinit(self.chunk);
                    }
                }
            }
            self.subscribers.deinit(self.chunk);
            self.clearDrops();
            self.dropped.deinit(self.chunk);
        }

        pub fn insert(
            self: *Self,
            key: Key,
            callback: anytype,
            context: anytype,
        ) !Subscription {
            const Context = @TypeOf(context);
            const SIZE = @sizeOf(Context);
            const ALIGN = @alignOf(Context);

            if (SIZE > MAX_SIZE or
                ALIGN > MAX_ALIGN.toByteUnits())
            {
                panic("Wrong Context: size: {}, align: {}", .{ SIZE, ALIGN });
            }

            const TypeErased = struct {
                fn _callback(sub: Subscriber, args: Args) bool {
                    const _context: *const Context = @ptrCast(@alignCast(sub.context));
                    return @call(.always_inline, callback, args ++ _context.*);
                }
            };

            const id = self.next_id;
            self.next_id += 1;

            const context_buffer = (self.chunk.rawAlloc(
                MAX_SIZE,
                MAX_ALIGN,
                @returnAddress(),
            ) orelse return error.OutOfMemory)[0..MAX_SIZE];
            errdefer self.chunk.rawFree(context_buffer, MAX_ALIGN, @returnAddress());

            const context_ptr: *Context = @ptrCast(@alignCast(context_buffer.ptr));
            context_ptr.* = context;

            const sub = Subscriber{
                .active = false,
                .callback = TypeErased._callback,
                .context = context_ptr,
            };

            if (self.subscribers.get_ref(key)) |subs| {
                const old = try subs.*.?.insert(self.chunk, id, sub);
                assert(old == null);
            } else {
                var subscribers: SubscriberTree = undefined;
                try subscribers.init(self.chunk);
                errdefer subscribers.deinit(self.chunk);

                _ = try subscribers.insert(self.chunk, id, sub);
                _ = try self.subscribers.insert(self.chunk, key, subscribers);
            }

            return .{ .subscriptions = self, .key = key, .id = id };
        }

        pub fn enable(self: *Self, sub: *const Subscription) void {
            const maybe_subscribers = self.subscribers.get_ref(sub.key) orelse return;
            if (maybe_subscribers.*) |*subscribers| {
                const subscriber = subscribers.get_ref(sub.id) orelse return;
                subscriber.active = true;
            }
        }

        pub fn notifyAll(self: *Self, key: Key, args: Args) void {
            const maybe_subscribers = self.subscribers.get_ref(key) orelse return;
            var subscribers = maybe_subscribers.* orelse return;

            var iter = subscribers.iter();
            while (iter.next()) |entry| {
                if (entry.value.active and !entry.value.callback(entry.value, args)) {
                    _ = self.dropped.insert(self.chunk, .{ .key = key, .id = entry.key }) catch |err| {
                        debug.panic("Drop subscriber err: {}", .{err});
                    };
                }
            }

            self.clearDrops();
        }

        pub fn notify(self: *Self, sub: *const Subscription, args: Args) bool {
            defer self.clearDrops();
            const maybe_subscribers = self.subscribers.get_ref(sub.key) orelse return false;
            var subscribers = maybe_subscribers.* orelse return false;
            const subscriber = subscribers.get(sub.id) orelse return false;

            if (!subscriber.active) return false;

            if (!subscriber.callback(subscriber, args)) {
                _ = self.dropped.insert(self.chunk, .{ .key = sub.key, .id = sub.id }) catch |err| {
                    debug.panic("Drop subscriber err: {}", .{err});
                };
            }

            return true;
        }

        pub fn clearDrops(self: *Self) void {
            var dropped = self.dropped.iter();
            while (dropped.next()) |drop| {
                const maybe_dropped_subscribers = self.subscribers.get_ref(drop.key) orelse {
                    _ = self.dropped.remove(self.chunk, drop);
                    continue;
                };
                var dropped_subscribers = maybe_dropped_subscribers.* orelse {
                    _ = self.dropped.remove(self.chunk, drop);
                    continue;
                };
                if (dropped_subscribers.remove(self.chunk, drop.id)) |sub| {
                    self.destroyContext(sub);
                }

                _ = self.dropped.remove(self.chunk, drop);

                if (dropped_subscribers.is_empty()) {
                    dropped_subscribers.deinit(self.chunk);
                    _ = self.subscribers.remove(self.chunk, drop.key);
                } else {
                    maybe_dropped_subscribers.* = dropped_subscribers;
                }
            }
        }

        pub fn remove(self: *Self, key: Key) void {
            if (self.subscribers.remove(self.chunk, key)) |subscribers| {
                if (subscribers) |subs| {
                    var mutable_subs = subs;
                    self.destroyContexts(&mutable_subs);
                    mutable_subs.deinit(self.chunk);
                }
            }
        }

        pub fn unsubscribe(self: *Self, sub: *const Subscription) !void {
            const maybe_subscribers = self.subscribers.get_ref(sub.key) orelse return;
            if (maybe_subscribers.*) |*subs| {
                if (subs.remove(self.chunk, sub.id)) |removed| {
                    self.destroyContext(removed);
                }
                if (subs.is_empty()) {
                    subs.deinit(self.chunk);
                    _ = self.subscribers.remove(self.chunk, sub.key);
                }
            } else {
                _ = try self.dropped.insert(self.chunk, .{ .id = sub.id, .key = sub.key });
            }
        }

        fn destroyContexts(self: *Self, subscribers: *SubscriberTree) void {
            var iter = subscribers.iter();
            while (iter.next()) |entry| {
                self.destroyContext(entry.value);
            }
        }

        fn destroyContext(self: *Self, sub: Subscriber) void {
            self.chunk.rawFree(
                @as([*]u8, @ptrCast(sub.context))[0..MAX_SIZE],
                MAX_ALIGN,
                @returnAddress(),
            );
        }
    };
}

test "Subscriptions" {
    const Key = u32;
    const Order = struct {
        pub fn order(a: Key, b: Key) std.math.Order {
            return std.math.order(a, b);
        }
    };

    const Callback = struct {
        fn notify(value: bool, keep: bool, run: *bool) bool {
            run.* = value;
            return keep;
        }
    };

    const Subs = Subscriptions(Key, @Tuple(&.{ bool, bool }), Order.order);

    var chunks: ChunkAllocator = undefined;
    try chunks.init(std.testing.allocator, &.{.{ 100, Subs.NODE_SIZE }});
    defer chunks.deinit(std.testing.allocator);

    var subscriptions: Subs = undefined;
    try subscriptions.init(chunks.allocator());
    defer subscriptions.deinit();

    const key = 42;
    var context = false;
    var sub = try subscriptions.insert(key, Callback.notify, .{&context});

    try std.testing.expectEqual(&subscriptions, sub.subscriptions);
    try std.testing.expectEqual(@as(Key, 42), sub.key);
    try std.testing.expectEqual(@as(u32, 0), sub.id);
    try std.testing.expectEqual(@as(u32, 1), subscriptions.next_id);

    const subscribers = subscriptions.subscribers.get_ref(42).?;
    const subscriber = subscribers.*.?.get(0).?;
    try std.testing.expect(!subscriber.active);

    subscriptions.notifyAll(42, .{ true, true });
    try std.testing.expect(!context);

    sub.enable();

    subscriptions.notifyAll(42, .{ true, true });
    subscriptions.notifyAll(24, .{ false, false });
    try std.testing.expect(context);

    subscriptions.notifyAll(42, .{ false, false });
    try std.testing.expect(subscriptions.subscribers.get_ref(42) == null);
}

test "Subscription notifies only its subscriber" {
    const Key = u32;
    const Order = struct {
        pub fn order(a: Key, b: Key) std.math.Order {
            return std.math.order(a, b);
        }
    };

    const Callback = struct {
        fn notify(value: u32, keep: bool, result: *u32) bool {
            result.* = value;
            return keep;
        }
    };

    const Subs = Subscriptions(Key, @Tuple(&.{ u32, bool }), Order.order);

    var chunks: ChunkAllocator = undefined;
    try chunks.init(std.testing.allocator, &.{.{ 100, Subs.NODE_SIZE }});
    defer chunks.deinit(std.testing.allocator);

    var subscriptions: Subs = undefined;
    try subscriptions.init(chunks.allocator());
    defer subscriptions.deinit();

    var first_result: u32 = 0;
    var second_result: u32 = 0;
    var first = try subscriptions.insert(42, Callback.notify, .{&first_result});
    var second = try subscriptions.insert(42, Callback.notify, .{&second_result});
    first.enable();
    second.enable();

    _ = first.notify(.{ 35, true });

    try std.testing.expectEqual(@as(u32, 35), first_result);
    try std.testing.expectEqual(@as(u32, 0), second_result);

    _ = first.notify(.{ 70, false });

    try std.testing.expectEqual(@as(u32, 70), first_result);
    try std.testing.expect(subscriptions.subscribers.get_ref(42).?.*.?.get(first.id) == null);
    try std.testing.expect(subscriptions.subscribers.get_ref(42).?.*.?.get(second.id) != null);
}
