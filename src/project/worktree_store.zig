const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const App = @import("../app.zig");
const Context = App.Context;
const ent = @import("../entity.zig");
const AnyEntity = ent.AnyEntity;
const Worktree = @import("../worktree.zig");

const WorktreeStore = @This();

pub const Options = struct {
    arena: Allocator,
    paths: []const []const u8,
    io: Io,
};

any: AnyEntity,
worktrees: std.AutoHashMap(u8, *Worktree),
next_id: u8,

pub fn init(self: *WorktreeStore, any: AnyEntity, app: *App, options: Options) !void {
    self.* = .{
        .any = any,
        .next_id = 0,
        .worktrees = .init(options.arena),
    };
    errdefer _ = self.drop();

    for (options.paths) |path| {
        const id = self.next_id;
        const worktree = try app.new(Worktree, Worktree.init, .{
            options.io,
            path,
        });
        errdefer worktree.drop();

        try self.worktrees.put(id, worktree);
        self.next_id += 1;
    }
}

pub fn drop(self: *WorktreeStore) void {
    self.any.drop();
    var iter = self.worktrees.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.*.drop();
    }
}
