const std = @import("std");
const Scanner = @import("worktree/scanner/mod.zig");

pub const EventType = enum {
    worktree_updated,
};

pub const EventData = union(EventType) {
    worktree_updated: *Scanner.UpdatedEntriesSet,
};

pub const Callback = *const fn (data: EventData, userdata: ?*anyopaque) void;

pub const Subscription = struct {
    callback: Callback,
    userdata: ?*anyopaque,
};

pub const SubscriptionList = std.ArrayListUnmanaged(Subscription);
pub const Listeners = std.EnumArray(EventType, SubscriptionList);
