const std = @import("std");
const vaxis = @import("vaxis");
const UpdatedEntriesSet = @import("../worktree/scanner/mod.zig").UpdatedEntriesSet;

pub const Callback = *const fn (userdata: ?*anyopaque, EventData) void;

pub const EventType = enum {
    scheme,
    worktreeUpdatedEntries,
    bufferUpdated,
};

pub const EventData = union(EventType) {
    scheme: vaxis.Color.Scheme,
    worktreeUpdatedEntries: *UpdatedEntriesSet,
    bufferUpdated: u64,
};

fn noop(_: ?*anyopaque, _: EventData) void {}

pub const Subscription = struct {
    userdata: ?*anyopaque = null,
    callback: Callback = noop,
};

pub const EventSubscriptions = std.ArrayList(Subscription);
pub const Subscriptions = std.EnumArray(EventType, EventSubscriptions);

pub fn EventListeners(EventType: type, EventData: type) type {
    return struct {
        pub const Callback = *const fn (userdata: ?*anyopaque, EventData) void;

        fn noop(_: ?*anyopaque, _: EventData) void {}

        pub const Listener = struct {
            userdata: ?*anyopaque = null,
            callback: Callback = noop,
        };
        pub const EventListeners = std.ArrayList(Listener);
        pub const Listeners = std.EnumArray(EventType, EventListeners);

        listeners: Listeners,
    };
}
