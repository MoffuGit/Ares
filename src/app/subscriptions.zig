const std = @import("std");
const vaxis = @import("vaxis");
const UpdatedEntriesSet = @import("../worktree/scanner/mod.zig").UpdatedEntriesSet;

pub const Callback = *const fn (userdata: ?*anyopaque, EventData) void;

pub const EventType = enum {
    scheme,
    worktreeUpdatedEntries,
};

pub const EventData = union(EventType) {
    scheme: vaxis.Color.Scheme,
    worktreeUpdatedEntries: *UpdatedEntriesSet,
};

fn noop(_: ?*anyopaque, _: EventData) void {}

pub const Subscription = struct {
    userdata: ?*anyopaque = null,
    callback: Callback = noop,
};

pub const EventSubscriptions = std.ArrayList(Subscription);
pub const Subscriptions = std.EnumArray(EventType, EventSubscriptions);
