const std = @import("std");
const BlockingQueue = @import("datastruct").BlockingQueue;
const Waker = @import("Waker.zig");
const keymapspkg = @import("keymaps/mod.zig");
const UpdatedEntriesSet = @import("worktree/scanner/mod.zig").UpdatedEntriesSet;

pub const EventTag = enum {
    worktree_updated,
    buffer_updated,
    settings_changed,
    keymap_actions,
};

pub const Event = union(EventTag) {
    worktree_updated: *UpdatedEntriesSet,
    buffer_updated: u64,
    settings_changed: void,
    keymap_actions: []const keymapspkg.Action,
};

pub const Queue = BlockingQueue(Event, 256);

const EventQueue = @This();

queue: *Queue,
waker: Waker,
alloc: std.mem.Allocator,

pub fn init(alloc: std.mem.Allocator, waker: Waker) !EventQueue {
    const queue = try Queue.create(alloc);
    return .{
        .queue = queue,
        .waker = waker,
        .alloc = alloc,
    };
}

pub fn deinit(self: *EventQueue) void {
    self.queue.destroy(self.alloc);
}

pub fn push(self: *EventQueue, event: Event) void {
    if (self.queue.push(event, .instant) != 0) {
        self.waker.wake();
    }
}

pub fn poll(self: *EventQueue) ?Event {
    return self.queue.pop();
}
