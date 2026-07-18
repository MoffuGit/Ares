const std = @import("std");
const Allocator = std.mem.Allocator;
const App = @import("../app.zig");
const Entity = App.Entity;
const Context = App.Context;
const Worktree = @import("../worktree.zig");

const WorktreeStore = @This();

worktrees: std.AutoHashMap(u8, Entity(Worktree)),
next_id: u8,

pub fn init(self: *WorktreeStore, _: Context(WorktreeStore), arena: Allocator) !void {
    self.* = .{
        .next_id = 0,
        .worktrees = .init(arena),
    };
}

pub fn drop(self: *WorktreeStore) void {
    var iter = self.worktrees.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.drop();
    }
}

pub fn deinit(self: *WorktreeStore) void {
    _ = self;
}
