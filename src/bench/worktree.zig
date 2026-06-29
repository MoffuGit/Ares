const std = @import("std");
const testing = std.testing;
const prof = @import("prof");
const test_build = @import("test_build");
const Worktree = @import("../worktree.zig");
const App = @import("../app.zig");
const Entity = App.Entity;

const WorktreeScanObserver = struct {
    scanning: bool,

    pub fn init(self: *@This(), _: App.Context(@This())) !void {
        self.* = .{ .scanning = true };
    }

    pub fn observe(self: *@This(), worktree: Entity(Worktree), ctx: App.Context(@This())) void {
        self.scanning = worktree.read(ctx.app).scanning;
    }
};

test "Bench Worktree" {
    const gpa = std.heap.c_allocator;
    const io = testing.io;

    var app: App = undefined;
    try app.init(gpa, io);
    defer app.deinit();

    var bench: prof.Benchmark = undefined;
    bench.init(gpa, .{ .max_iter = 1, .name = "WORKTREE" });
    defer bench.deinit();

    const res = try bench.run(App, &app, gpa, io, initialWorktreeScan);
    try res.log(io, .stdout());
}

pub fn initialWorktreeScan(app: *App, gpa: std.mem.Allocator, io: std.Io, _: *prof.Profiler) !void {
    var alloc: std.heap.ArenaAllocator = .init(gpa);
    defer alloc.deinit();
    const arena = alloc.allocator();

    defer app.flush();

    const worktree: Entity(Worktree) = try .new(
        app,
        .{
            io,
            arena,
            Worktree.Options{ .abs_path = test_build.chromium_path },
        },
    );
    defer worktree.drop();

    const observer = try Entity(WorktreeScanObserver).new(app, .{});
    defer observer.drop();

    var ctx = App.Context(WorktreeScanObserver).new(app, observer);
    _ = try ctx.observe(worktree, WorktreeScanObserver.observe, .{});

    while (observer.read(app).scanning) {
        app.flush();
    }

    std.log.debug("entries: {}", .{worktree.read(app).snapshot.entries.count});
}
