const std = @import("std");
const Allocator = std.mem.Allocator;
const debug = std.debug;

const datastruct = @import("datastruct.zig");
const btree = datastruct.btree;
const assert = debug.assert;

pub fn Subscriptions(Key: type, comptime types: []const type, comptime comp: *const fn (Key, Key) std.math.Order) type {
    return struct {
        const Self = @This();

        const Args = @Tuple(types);

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
            context: []u8,
            alignment: u8,

            fn free(self: Subscriber, gpa: Allocator) void {
                gpa.rawFree(self.context, .fromByteUnits(self.alignment), @returnAddress());
            }
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

            pub fn unsubscribe(self: *const Subscription, gpa: Allocator) !void {
                try self.subscriptions.unsubscribe(self, gpa);
            }
        };

        subscribers: Subscribers,
        dropped: btree.BPlusSet(Dropped, Dropped.order),
        next_id: u32,

        pub fn init(self: *Self, gpa: Allocator) !void {
            self.* = .{
                .next_id = 0,
                .subscribers = undefined,
                .dropped = undefined,
            };

            try self.subscribers.init(gpa);
            errdefer self.subscribers.deinit(gpa);

            try self.dropped.init(gpa);
            errdefer self.dropped.deinit(gpa);
        }

        pub fn deinit(self: *Self, gpa: Allocator) void {
            var outer = self.subscribers.iter();
            while (outer.next()) |entry| {
                if (self.subscribers.get_ref(entry.key)) |maybe_subscribers| if (maybe_subscribers.*) |*subscribers| {
                    var inner = subscribers.iter();
                    while (inner.next()) |subscriber| {
                        const sub = subscriber.value;
                        sub.free(gpa);
                    }
                    subscribers.deinit(gpa);
                };
            }
            self.subscribers.deinit(gpa);
            self.clearDrops(gpa);
            self.dropped.deinit(gpa);
        }

        pub fn insert(
            self: *Self,
            key: Key,
            callback: anytype,
            context: anytype,
            gpa: Allocator,
        ) !Subscription {
            const Context = @TypeOf(context);

            const TypeErased = struct {
                fn _callback(sub: Subscriber, args: Args) bool {
                    const _context: *Context = @ptrCast(@alignCast(sub.context.ptr));
                    return @call(.auto, callback, args ++ _context.*);
                }
            };

            const id = self.next_id;
            self.next_id += 1;

            const copy = try gpa.create(Context);
            errdefer gpa.destroy(copy);
            copy.* = context;

            const sub = Subscriber{
                .active = false,
                .callback = TypeErased._callback,
                .context = @ptrCast(copy),
                .alignment = @alignOf(Context),
            };

            if (self.subscribers.get_ref(key)) |subs| {
                const old = try subs.*.?.insert(gpa, id, sub);
                assert(old == null);
            } else {
                var subscribers: btree.BPlusTree(u32, Subscriber, Order.order) = undefined;
                try subscribers.init(gpa);
                errdefer {
                    sub.free(gpa);
                    subscribers.deinit(gpa);
                }

                _ = try subscribers.insert(gpa, id, sub);
                _ = try self.subscribers.insert(gpa, key, subscribers);
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

        pub fn notify(self: *Self, key: Key, args: Args, gpa: Allocator) void {
            const maybe_subscribers = self.subscribers.get_ref(key) orelse return;
            var subscribers = maybe_subscribers.* orelse return;

            var iter = subscribers.iter();
            while (iter.next()) |entry| {
                if (entry.value.active and !entry.value.callback(entry.value, args)) {
                    _ = self.dropped.insert(gpa, .{ .key = key, .id = entry.key }) catch |err| {
                        debug.panic("Drop subscriber err: {}", .{err});
                    };
                }
            }

            self.clearDrops(gpa);
        }

        pub fn clearDrops(self: *Self, gpa: Allocator) void {
            var dropped = self.dropped.iter();
            while (dropped.next()) |drop| {
                const maybe_dropped_subscribers = self.subscribers.get_ref(drop.key) orelse {
                    _ = self.dropped.remove(gpa, drop);
                    continue;
                };
                var dropped_subscribers = maybe_dropped_subscribers.* orelse {
                    _ = self.dropped.remove(gpa, drop);
                    continue;
                };

                if (dropped_subscribers.remove(gpa, drop.id)) |removed| {
                    removed.free(gpa);
                }
                _ = self.dropped.remove(gpa, drop);

                if (dropped_subscribers.is_empty()) {
                    dropped_subscribers.deinit(gpa);
                    _ = self.subscribers.remove(gpa, drop.key);
                } else {
                    maybe_dropped_subscribers.* = dropped_subscribers;
                }
            }
        }

        pub fn remove(self: *Self, key: Key, gpa: Allocator) void {
            if (self.subscribers.remove(gpa, key)) |subscribers| {
                if (subscribers) |subs| {
                    var owned_subs = subs;
                    var iter = owned_subs.iter();
                    while (iter.next()) |entry| {
                        entry.value.free(entry.value.context, gpa);
                    }
                    owned_subs.deinit(gpa);
                }
            }
        }

        pub fn unsubscribe(self: *Self, sub: *const Subscription, gpa: Allocator) !void {
            var subscribers = self.subscribers.get(sub.key) orelse return;
            if (subscribers) |*subs| {
                if (subs.remove(gpa, sub.id)) |removed| {
                    removed.free(gpa);
                }
                if (subs.is_empty()) {
                    subs.deinit(gpa);
                    _ = self.subscribers.remove(gpa, sub.key);
                }
            } else {
                _ = try self.dropped.insert(gpa, .{ .id = sub.id, .key = sub.key });
            }
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

    const Subs = Subscriptions(Key, &.{ bool, bool }, Order.order);

    var subscriptions: Subs = undefined;
    try subscriptions.init(std.testing.allocator);
    defer subscriptions.deinit(std.testing.allocator);

    const key = 42;
    var context = false;
    var sub = try subscriptions.insert(key, Callback.notify, .{&context}, std.testing.allocator);

    try std.testing.expectEqual(&subscriptions, sub.subscriptions);
    try std.testing.expectEqual(@as(Key, 42), sub.key);
    try std.testing.expectEqual(@as(u32, 0), sub.id);
    try std.testing.expectEqual(@as(u32, 1), subscriptions.next_id);

    const subscribers = subscriptions.subscribers.get_ref(42).?;
    const subscriber = subscribers.*.?.get(0).?;
    try std.testing.expect(!subscriber.active);

    subscriptions.notify(42, .{ true, true }, std.testing.allocator);
    try std.testing.expect(!context);

    sub.enable();

    subscriptions.notify(42, .{ true, true }, std.testing.allocator);
    subscriptions.notify(24, .{ false, false }, std.testing.allocator);
    try std.testing.expect(context);

    subscriptions.notify(42, .{ false, false }, std.testing.allocator);
    try std.testing.expect(subscriptions.subscribers.get_ref(42) == null);
}
