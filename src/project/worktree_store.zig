const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const App = @import("../app.zig");
const Context = App.Context;
const ent = @import("../entity.zig");
const Entity = ent.Entity;
const Worktree = @import("../worktree.zig");

const WorktreeStore = @This();

pub const Options = struct {
    arena: Allocator,
    paths: []const []const u8,
    io: Io,
};

worktrees: std.AutoHashMap(u8, Entity(Worktree)),
next_id: u8,

pub fn init(self: *WorktreeStore, ctx: Context(WorktreeStore), options: Options) !void {
    self.* = .{
        .next_id = 0,
        .worktrees = .init(options.arena),
    };
    errdefer _ = self.drop();

    for (options.paths) |path| {
        const id = self.next_id;
        const worktree: Entity(Worktree) = try .new(ctx.app, .{
            options.io,
            Worktree.Options{ .abs_path = path },
        });
        errdefer worktree.drop();

        try self.worktrees.put(id, worktree);
        self.next_id += 1;
    }
}

pub fn drop(self: *WorktreeStore) bool {
    var iter = self.worktrees.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.drop();
    }

    return true;
}

pub fn deinit(self: *WorktreeStore) void {
    _ = self;
}
