const std = @import("std");
const Allocator = std.mem.Allocator;
const Worktree = @import("../mod.zig");

pub const Scanner = @This();

alloc: Allocator,
worktree: *Worktree,

pub fn init(alloc: Allocator, worktree: *Worktree) !Scanner {
    return .{ .alloc = alloc, .worktree = worktree };
}

pub fn deinit(self: *Scanner) void {
    _ = self;
}

//the work of the scanner is receive the root path
//and then iterating over the subpaths of root
//every time you find a directory you would send a message to the monitor for
//adding the watcher
//
//after the first scan the two things that can happen are, a new root, you need to make the first scan again
//or an event got trigger on the monitor, what you do next in this case would depend on the type of event
