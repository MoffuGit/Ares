const std = @import("std");

pub fn EventListeners(comptime EType: type, comptime EData: type) type {
    return struct {
        const Self = @This();

        pub const EventType = EType;
        pub const EventData = EData;
        pub const Callback = *const fn (userdata: ?*anyopaque, EData) void;

        fn noop(_: ?*anyopaque, _: EData) void {}

        pub const Listener = struct {
            userdata: ?*anyopaque = null,
            callback: Callback = noop,
        };

        const ListenerList = std.ArrayList(Listener);
        const Listeners = std.EnumArray(EType, ListenerList);

        values: Listeners = .initFill(.{}),

        pub fn addSubscription(
            self: *Self,
            alloc: std.mem.Allocator,
            event: EType,
            comptime Userdata: type,
            userdata: *Userdata,
            cb: *const fn (userdata: *Userdata, data: EData) void,
        ) !void {
            try self.values.getPtr(event).append(alloc, .{
                .userdata = userdata,
                .callback = @ptrCast(cb),
            });
        }

        pub fn notify(self: *Self, data: EData) void {
            const list = self.values.get(@as(EType, data));
            for (list.items) |sub| {
                sub.callback(sub.userdata, data);
            }
        }

        pub fn notifyConsumable(self: *Self, data: EData, consumed: *bool) void {
            const list = self.values.get(@as(EType, data));
            for (list.items) |sub| {
                sub.callback(sub.userdata, data);
                if (consumed.*) break;
            }
        }

        pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
            for (&self.values.values) |*list| {
                list.deinit(alloc);
            }
        }
    };
}
