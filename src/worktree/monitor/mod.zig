const std = @import("std");
const xev = @import("../../global.zig").xev;
const Allocator = std.mem.Allocator;
const Worktree = @import("../mod.zig");

pub const Monitor = @This();

alloc: Allocator,
watchers: std.AutoHashMap(usize, xev.Watcher),
worktree: *Worktree,

pub fn init(alloc: Allocator, worktree: *Worktree) !Monitor {
    return .{ .watchers = .init(alloc), .alloc = alloc, .worktree = worktree };
}

pub fn deinit(self: *Monitor) void {
    self.watchers.deinit();
}

//You are going to receive events from the scanner
//for adding or removing watchers, then, when a watcher notify an event, you would send
//this event to the scanner for re scanning given path
//
//after removing a watcher you don't delete it instantly
//you add it to a special queue, on the next loop tick
//you check if the watcher is dead, then if the watcher is dead, you can
//deallocate it
