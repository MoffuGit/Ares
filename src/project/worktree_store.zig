const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const App = @import("../app.zig");
const Entity = App.Entity;
const Context = App.Context;
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
    errdefer self.drop();

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

pub fn drop(self: *WorktreeStore) void {
    var iter = self.worktrees.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.drop();
    }
}

pub fn deinit(self: *WorktreeStore) void {
    _ = self;
}

test "WorktreeStore creates a worktree per path" {
    const testing = std.testing;
    const gpa = testing.allocator;
    const io = testing.io;
    const test_build = @import("test_build");

    var app: App = undefined;
    try app.init(.{}, gpa, io);
    defer app.deinit();

    const paths = [_][]const u8{test_build.chromium_path};

    const store: Entity(WorktreeStore) = try .new(
        &app,
        .{
            WorktreeStore.Options{
                .arena = app.arena.allocator(),
                .paths = &paths,
                .io = io,
            },
        },
    );
    errdefer store.drop();

    try testing.expectEqual(@as(usize, 1), store.read(&app).worktrees.count());
    try testing.expectEqual(@as(u8, 1), store.read(&app).next_id);

    store.drop();
    app.flush();
}
