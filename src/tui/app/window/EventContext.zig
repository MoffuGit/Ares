const std = @import("std");

const Element = @import("element/mod.zig").Element;

pub const Phase = enum {
    capturing,
    at_target,
    bubbling,
};

pub const EventContext = @This();

phase: Phase = .capturing,
target: *Element,
stopped: bool = false,

pub fn stopPropagation(self: *EventContext) void {
    self.stopped = true;
}

pub fn isStopped(self: *const EventContext) bool {
    return self.stopped;
}
