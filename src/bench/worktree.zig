const std = @import("std");
const testing = std.testing;
const prof = @import("prof");
const Worktree = @import("../worktree.zig");

test "Bench Worktree" {
    const gpa = testing.allocator;
    const io = testing.io;

    var bench: prof.Benchmark = undefined;
    bench.init(gpa, .{
        .max_iter = 1,
    });
    defer bench.deinit();

    const res = try bench.run(void, undefined, gpa, io, initialWorktreeScan);
    try res.log(io, .stdout());
}

pub fn initialWorktreeScan(_: *void, alloc: std.mem.Allocator, io: std.Io, _: *prof.Profiler) !void {
    var worktree: Worktree = undefined;
    try worktree.init(alloc, io, .{
        .abs_path = "/Volumes/Home_SSD/Users/home/Documents/projects/Odyssey/testdata/chromium",
    });
    defer worktree.deinit();

    std.log.err("cnt: {}", .{worktree.scanner.state.list.items.len});
}
