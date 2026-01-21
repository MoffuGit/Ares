const std = @import("std");

const Element = @import("../element/Element.zig");

pub const Phase = enum {
    capturing,
    at_target,
    bubbling,
};

pub const EventContext = @This();

phase: Phase,
target: ?*Element,
stopped: bool = false,
default_prevented: bool = false,

pub fn stopPropagation(self: *EventContext) void {
    self.stopped = true;
}

pub fn preventDefault(self: *EventContext) void {
    self.default_prevented = true;
}

pub fn isStopped(self: *const EventContext) bool {
    return self.stopped;
}

pub fn isDefaultPrevented(self: *const EventContext) bool {
    return self.default_prevented;
}
