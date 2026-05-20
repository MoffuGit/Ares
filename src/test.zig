const std = @import("std");
const testing = std.testing;
const Worktree = @import("worktree.zig");

test "worktree" {
    const gpa = testing.allocator;
    const io = testing.io;
    var worktree: Worktree = undefined;
    try worktree.init(gpa, io, .{
        .abs_path = "/Volumes/Home_SSD/Users/home/Documents/projects/Odyssey/testdata/chromium",
    });
    defer worktree.deinit();
}
