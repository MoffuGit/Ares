const std = @import("std");

pub fn EventListeners(comptime EType: type, comptime EData: type) type {
    return struct {
        const Self = @This();

        pub const EventType = EType;
        pub const EventData = EData;
        pub const Callback = *const fn (userdata: ?*anyopaque, EData) void;

        fn noop(_: ?*anyopaque, _: EData) void {}

        pub const Subscription = struct {
            userdata: ?*anyopaque = null,
            callback: Callback = noop,
        };

        const SubscriptionList = std.ArrayList(Subscription);
        const Subs = std.EnumArray(EType, SubscriptionList);

        subs: Subs = .initFill(.{}),

        pub fn addSubscription(
            self: *Self,
            alloc: std.mem.Allocator,
            event: EType,
            comptime Userdata: type,
            userdata: *Userdata,
            cb: *const fn (userdata: *Userdata, data: EData) void,
        ) !void {
            try self.subs.getPtr(event).append(alloc, .{
                .userdata = userdata,
                .callback = @ptrCast(cb),
            });
        }

        pub fn notify(self: *Self, data: EData) void {
            const list = self.subs.get(@as(EType, data));
            for (list.items) |sub| {
                sub.callback(sub.userdata, data);
            }
        }

        pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
            for (&self.subs.values) |*list| {
                list.deinit(alloc);
            }
        }
    };
}
