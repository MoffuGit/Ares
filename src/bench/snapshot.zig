const std = @import("std");
const testing = std.testing;
const prof = @import("prof");
const Snapshot = @import("../worktree/snapshot.zig");

const Context = struct {
    snapshot: *Snapshot,
    paths: *std.ArrayList([]const u8),
};

test "Bench Worktree" {
    const gpa = testing.allocator;
    var alloc = std.heap.ArenaAllocator.init(gpa);
    defer _ = alloc.reset(.free_all);

    const arena = alloc.allocator();
    const io = testing.io;

    const abs_root = "/Volumes/Home_SSD/Users/home/Documents/projects/Odyssey/testdata/chromium";
    const basename = std.fs.path.basename(abs_root);
    const root_name = try arena.dupe(u8, basename);

    var paths: std.ArrayList([]const u8) = .empty;
    defer paths.deinit(gpa);

    var dir = try std.Io.Dir.openDirAbsolute(io, abs_root, .{ .iterate = true });
    defer dir.close(io);

    var walker = try dir.walk(gpa);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        const child_path = try std.fs.path.join(arena, &.{ root_name, entry.path });
        try paths.append(gpa, child_path);
    }

    var snapshot: Snapshot = undefined;
    try snapshot.init(abs_root, root_name, gpa);
    defer snapshot.deinit(gpa);

    var bench: prof.Benchmark = undefined;
    bench.init(gpa, .{
        .stop_ms = 20000,
    });
    defer bench.deinit();

    var context: Context = .{ .snapshot = &snapshot, .paths = &paths };

    const res = try bench.run(Context, &context, gpa, io, fillSnapshot);
    try res.log(io, .stdout());
}

pub fn fillSnapshot(context: *Context, alloc: std.mem.Allocator, _: std.Io, _: *prof.Profiler) !void {
    const snapshot = context.snapshot;
    const paths = context.paths;

    for (paths.items) |path| {
        try snapshot.insert(alloc, path);
    }
}
