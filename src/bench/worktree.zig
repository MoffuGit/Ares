const std = @import("std");
const testing = std.testing;
const prof = @import("prof");
const test_build = @import("test_build");
const Worktree = @import("../worktree.zig");

test "Bench Worktree" {
    const gpa = testing.allocator;
    const io = testing.io;

    var bench: prof.Benchmark = undefined;
    bench.init(gpa, .{ .stop_ms = 20000, .name = "WORKTREE" });
    defer bench.deinit();

    const res = try bench.run(void, undefined, gpa, io, initialWorktreeScan);
    try res.log(io, .stdout());
}

pub fn initialWorktreeScan(_: *void, alloc: std.mem.Allocator, io: std.Io, _: *prof.Profiler) !void {
    var worktree: Worktree = undefined;
    try worktree.init(alloc, .{
        .abs_path = test_build.chromium_path,
    });
    defer worktree.deinit();

    try worktree.run(io);
    try worktree.await(io);
}
