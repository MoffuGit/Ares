const std = @import("std");
const testing = std.testing;
const prof = @import("prof");
const test_build = @import("test_build");
const Worktree = @import("../worktree.zig");
const App = @import("../app.zig");
const Entity = App.Entity;

test "Bench Worktree" {
    const gpa = std.heap.c_allocator;
    const io = testing.io;

    var app: App = undefined;
    try app.init(gpa, io);
    defer app.deinit();

    var bench: prof.Benchmark = undefined;
    bench.init(gpa, .{ .stop_ms = 20000, .name = "WORKTREE" });
    defer bench.deinit();

    const res = try bench.run(App, &app, gpa, io, initialWorktreeScan);
    try res.log(io, .stdout());
}

pub fn initialWorktreeScan(app: *App, gpa: std.mem.Allocator, io: std.Io, _: *prof.Profiler) !void {
    const worktree: Entity(Worktree) = try .new(app, .{ gpa, Worktree.Options{ .abs_path = test_build.chromium_path } });
    defer {
        worktree.drop();
        app.flush() catch @panic("flush failed");
    }

    _ = worktree.update(
        app,
        struct {
            fn read(tree: *Worktree, _io: std.Io) void {
                tree.run(_io) catch return;
                tree.await(_io) catch return;
            }
        }.read,
        .{io},
    );
}
