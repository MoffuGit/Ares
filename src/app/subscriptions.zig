const std = @import("std");
const vaxis = @import("vaxis");

pub const Callback = *const fn (userdata: ?*anyopaque, EventData) void;

pub const EventType = enum {
    scheme,
};

pub const EventData = union(EventType) {
    scheme: vaxis.Color.Scheme,
};

fn noop(_: ?*anyopaque, _: EventData) void {}

pub const Subscription = struct {
    userdata: ?*anyopaque = null,
    callback: Callback = noop,
};

pub const EventSubscriptions = std.ArrayList(Subscription);
pub const Subscriptions = std.EnumArray(EventType, EventSubscriptions);
