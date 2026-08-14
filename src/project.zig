const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const App = @import("app.zig");
const Context = App.Context;
const ent = @import("entity.zig");
const AnyEntity = ent.AnyEntity;
const WorktreeStore = @import("project/worktree_store.zig");

const Project = @This();

pub const Options = struct {
    arena: Allocator,
    paths: []const []const u8,
    io: Io,
};

any: AnyEntity,
arena: Allocator,
worktree_store: *WorktreeStore,

pub fn init(self: *Project, any: AnyEntity, app: *App, options: Options) !void {
    self.* = .{
        .any = any,
        .arena = options.arena,
        .worktree_store = try app.new(WorktreeStore, WorktreeStore.init, .{
            WorktreeStore.Options{
                .arena = options.arena,
                .paths = options.paths,
                .io = options.io,
            },
        }),
    };
}

pub fn drop(self: *Project) void {
    self.any.drop();
    self.worktree_store.drop();
}
