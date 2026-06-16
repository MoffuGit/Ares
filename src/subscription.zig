const std = @import("std");
const Allocator = std.mem.Allocator;
const debug = std.debug;

const datastruct = @import("datastruct.zig");
const btree = datastruct.btree;

pub fn Subscriptions(Key: type, Args: type, comptime comp: *const fn (Key, Key) std.math.Order) type {
    return struct {
        const Self = @This();

        const Callback = *const fn (.{Args ++ ?*anyopaque}) bool{};

        const Subscribers = btree.BPlusTree(Key, ?btree.BPlusTree(u32, Subscriber, std.math.order), comp);

        pub const Subscriber = struct {
            active: bool,
            callback: Callback,
            context: ?*anyopaque,
        };

        pub const Subscription = struct {
            subscriptions: *Self,
            key: Key,
            id: u32,

            pub fn unsubscribe(self: *Subscription) void {
                self.subscriptions.unsubscribe(self) catch |err| {
                    debug.panic("Unsubscribe err: {}", .{err});
                };
            }
        };

        gpa: Allocator,
        subscribers: Subscribers,
        next_id: u32,

        pub fn init(self: *Self, gpa: Allocator) !void {
            self.* = .{
                .gpa = gpa,
                .next_id = 0,
                .subscribers = undefined,
            };

            try self.subscribers.init(gpa);
        }

        pub fn unsubscribe(self: *Self, subscription: Subscription) !void {
            //     const subscribers = self.subscriptions.subscribers.get_ref(self.key) orelse return;
            //
            //     _ = subscribers.remove(self.subscriptions.gpa, self.key);
            //     if (subscribers.is_empty()) {
            //         self.subscriptions.subscribers.remove(self.subscriptions.gpa, self.key);
            //     }
        }

        pub fn deinit(self: *Self) void {
            self.subscribers.deinit(self.gpa);
        }
    };
}
