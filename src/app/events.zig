const std = @import("std");

pub fn EventListeners(comptime EType: type, comptime EData: type) type {
    return struct {
        const Self = @This();

        pub const EventType = EType;
        pub const EventData = EData;
        pub const Callback = *const fn (userdata: ?*anyopaque, EData) void;

        fn noop(_: ?*anyopaque, _: EData) void {}

        pub const Listener = struct {
            id: u64 = 0,
            userdata: ?*anyopaque = null,
            callback: Callback = noop,
        };

        const ListenerList = std.ArrayList(Listener);
        const Listeners = std.EnumArray(EType, ListenerList);

        values: Listeners = .initFill(.{}),
        next_id: u64 = 1,

        pub fn addSubscription(
            self: *Self,
            alloc: std.mem.Allocator,
            event: EType,
            comptime Userdata: type,
            userdata: *Userdata,
            cb: *const fn (userdata: *Userdata, data: EData) void,
        ) !u64 {
            const id = self.next_id;
            self.next_id +%= 1;
            try self.values.getPtr(event).append(alloc, .{
                .id = id,
                .userdata = userdata,
                .callback = @ptrCast(cb),
            });
            return id;
        }

        pub fn removeSubscription(self: *Self, event: EType, id: u64) void {
            const list = self.values.getPtr(event);
            for (list.items, 0..) |sub, i| {
                if (sub.id == id) {
                    _ = list.orderedRemove(i);
                    return;
                }
            }
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

        pub fn notifyConsumableReverse(self: *Self, data: EData, consumed: *bool) void {
            const items = self.values.get(@as(EType, data)).items;
            var i = items.len;
            while (i > 0) {
                i -= 1;
                items[i].callback(items[i].userdata, data);
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
