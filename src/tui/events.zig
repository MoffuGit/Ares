const std = @import("std");

pub fn EventListeners(comptime EventType: type, comptime EventData: type) type {
    return struct {
        const Self = @This();

        pub const Callback = *const fn (userdata: ?*anyopaque, EventData) void;

        fn noop(_: ?*anyopaque, _: EventData) void {}

        pub const Listener = struct {
            id: u64 = 0,
            userdata: ?*anyopaque = null,
            callback: Callback = noop,
        };

        const ListenerList = std.ArrayList(Listener);
        const Listeners = std.EnumArray(EventType, ListenerList);

        values: Listeners = .initFill(.{}),
        next_id: u64 = 1,

        pub fn addSubscription(
            self: *Self,
            alloc: std.mem.Allocator,
            event: EventType,
            comptime Userdata: type,
            userdata: *Userdata,
            comptime cb: *const fn (userdata: *Userdata, data: EventData) void,
        ) !u64 {
            const id = self.next_id;
            self.next_id +%= 1;
            try self.values.getPtr(event).append(alloc, .{
                .id = id,
                .userdata = userdata,
                .callback = (struct {
                    pub fn callback(inner_userdata: ?*anyopaque, inner_data: EventData) void {
                        cb(@as(*Userdata, @ptrCast(@alignCast(inner_userdata orelse return))), inner_data);
                    }
                }.callback),
            });
            return id;
        }

        pub fn removeSubscription(self: *Self, event: EventType, id: u64) void {
            const list = self.values.getPtr(event);
            for (list.items, 0..) |sub, i| {
                if (sub.id == id) {
                    _ = list.orderedRemove(i);
                    return;
                }
            }
        }

        pub fn notify(self: *Self, evt: EventType, data: EventData) void {
            const list = self.values.get(evt);
            for (list.items) |sub| {
                sub.callback(sub.userdata, data);
            }
        }

        pub fn notifyConsumable(self: *Self, evt: EventType, data: EventData, consumed: *bool) void {
            const list = self.values.get(evt);
            std.log.debug("len: {} type: {}", .{ list.items.len, evt });
            for (list.items) |sub| {
                std.log.debug("listener: {}", .{sub.id});
                sub.callback(sub.userdata, data);
                if (consumed.*) break;
            }
        }

        pub fn notifyConsumableReverse(self: *Self, evt: EventType, data: EventData, consumed: *bool) void {
            const items = self.values.get(evt).items;
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
