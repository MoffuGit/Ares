const std = @import("std");
const Allocator = std.mem.Allocator;
const debug = std.debug;

const datastruct = @import("datastruct.zig");
const btree = datastruct.btree;

pub fn Subscriptions(Key: type, comptime types: []const type, comptime comp: *const fn (Key, Key) std.math.Order) type {
    return struct {
        const Self = @This();

        const Args = @Tuple(types);

        const Callback = *const fn (Subscriber, Args) bool;

        const IdOrder = struct {
            fn order(a: u32, b: u32) std.math.Order {
                return std.math.order(a, b);
            }
        };

        const Subscribers = btree.BPlusTree(Key, ?btree.BPlusTree(u32, Subscriber, IdOrder.order), comp);

        pub const Subscriber = struct {
            callback: Callback,
            context: ?*anyopaque,
        };

        const Dropped = struct {
            key: Key,
            id: i32,
            pub fn order(a: Dropped, b: Dropped) std.math.Order {
                return std.math.order(a.id, b.id);
            }
        };

        pub const Subscription = struct {
            subscriptions: *Self,
            key: Key,
            id: u32,

            pub fn unsubscribe(self: *Subscription, gpa: Allocator) void {
                self.subscriptions.unsubscribe(self, gpa) catch |err| {
                    debug.panic("Unsubscribe err: {}", .{err});
                };
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
                    subscribers.deinit(gpa);
                };
            }
            self.subscribers.deinit(gpa);
            self.dropped.deinit(gpa);
        }

        pub fn insert(self: *Self, callback: anytype, context: anytype, gpa: Allocator) !Subscription {
            const Context = @TypeOf(context);

            const TypeErased = struct {
                fn _callback(sub: Subscriber, args: Args) bool {
                    const _context: Context = @ptrCast(@alignCast(sub.context));
                    return @call(.auto, callback, args ++ .{_context});
                }
            };

            const id = self.next_id;
            self.next_id += 1;

            const sub = Subscriber{
                .callback = TypeErased._callback,
                .context = context,
            };

            const key = context.key;
            if (self.subscribers.get_ref(key)) |maybe_subscribers| {
                if (maybe_subscribers.*) |*subscribers| {
                    _ = try subscribers.insert(gpa, id, sub);
                } else {
                    @panic("We lost our subscribers");
                }
            } else {
                var subscribers: btree.BPlusTree(u32, Subscriber, IdOrder.order) = undefined;
                try subscribers.init(gpa);
                errdefer subscribers.deinit(gpa);

                _ = try subscribers.insert(gpa, id, sub);
                _ = try self.subscribers.insert(gpa, key, subscribers);
            }

            return .{ .subscriptions = self, .key = key, .id = id };
        }

        pub fn notify(self: *Self, key: Key, args: Args) void {
            const maybe_subscribers = self.subscribers.get_ref(key) orelse return;
            var subscribers = maybe_subscribers.* orelse return;

            var iter = subscribers.iter();
            while (iter.next()) |entry| {
                _ = entry.value.callback(entry.value, args);
            }
        }

        pub fn remove(self: *Self, key: Key, gpa: Allocator) void {
            _ = self.subscribers.remove(gpa, key);
        }

        pub fn unsubscribe(self: *Self, sub: Subscription, gpa: Allocator) void {
            const subscribers = self.subscribers.get_ref(sub.key) orelse return;
            if (subscribers) |subs| {
                _ = subs.remove(gpa, sub.id);
                if (subs.is_empty()) {
                    _ = self.subscribers.remove(gpa, sub.key);
                }
            } else {
                self.dropped.insert(gpa, .{ .id = sub.id, .key = sub.key });
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
    const Context = struct {
        key: Key,
        notified: bool = false,
        notifications: u32 = 0,
    };
    const Callback = struct {
        fn notify(value: bool, context: *Context) bool {
            context.notified = value;
            context.notifications += 1;
            return value;
        }
    };

    const Subs = Subscriptions(Key, &.{bool}, Order.order);

    var subscriptions: Subs = undefined;
    try subscriptions.init(std.testing.allocator);
    defer subscriptions.deinit(std.testing.allocator);

    var context = Context{ .key = 42 };
    const sub = try subscriptions.insert(Callback.notify, &context, std.testing.allocator);

    try std.testing.expectEqual(&subscriptions, sub.subscriptions);
    try std.testing.expectEqual(@as(Key, 42), sub.key);
    try std.testing.expectEqual(@as(u32, 0), sub.id);
    try std.testing.expectEqual(@as(u32, 1), subscriptions.next_id);

    const subscribers = subscriptions.subscribers.get_ref(42).?;
    const subscriber = subscribers.*.?.get(0).?;
    try std.testing.expect(subscriber.callback(subscriber, .{true}));
    try std.testing.expect(context.notified);

    context.notified = false;
    subscriptions.notify(42, .{true});
    try std.testing.expect(context.notified);
    try std.testing.expectEqual(@as(u32, 2), context.notifications);

    subscriptions.notify(24, .{false});
    try std.testing.expect(context.notified);
    try std.testing.expectEqual(@as(u32, 2), context.notifications);
}
