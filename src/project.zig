const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const App = @import("app.zig");
const Context = App.Context;
const ent = @import("entity.zig");
const Entity = ent.Entity;
const WorktreeStore = @import("project/worktree_store.zig");

const Project = @This();

pub const Options = struct {
    arena: Allocator,
    paths: []const []const u8,
    io: Io,
};

arena: Allocator,
worktree_store: Entity(WorktreeStore),

pub fn init(self: *Project, ctx: Context(Project), options: Options) !void {
    self.* = .{
        .arena = options.arena,
        .worktree_store = try .new(ctx.app, .{
            WorktreeStore.Options{
                .arena = options.arena,
                .paths = options.paths,
                .io = options.io,
            },
        }),
    };
}

pub fn drop(self: *Project) void {
    self.worktree_store.drop();
}
