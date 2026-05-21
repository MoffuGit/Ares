const std = @import("std");
const testing = std.testing;
const Io = std.Io;
const prof = @import("prof");
const Snapshot = @import("../worktree/snapshot.zig");

const test_root = "/Volumes/Home_SSD/Users/home/Documents/projects/Odyssey/testdata/chromium";

const Context = struct {
    paths: [][]const u8,
    snapshot: *Snapshot,
};

test "Bench Snapshot.insert" {
    std.debug.print("Snapshot Test\n", .{});
    const gpa = testing.allocator;
    const io = testing.io;

    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var paths: std.ArrayList([]const u8) = .empty;
    defer paths.deinit(gpa);

    try paths.append(gpa, try arena.dupe(u8, test_root));
    try collectPaths(io, arena, gpa, &paths, test_root);

    std.debug.print("collected: {d} paths\n", .{paths.items.len});

    var snapshot: Snapshot = undefined;
    try snapshot.init(gpa);
    defer snapshot.deinit(gpa);

    var ctx: Context = .{ .paths = paths.items, .snapshot = &snapshot };

    var bench: prof.Benchmark = undefined;
    bench.init(gpa, .{
        .stop_ms = 20000,
    });
    defer bench.deinit();

    const res = try bench.run(Context, &ctx, gpa, io, runInsert);
    try res.log(io, .stdout());
}

fn runInsert(ctx: *Context, alloc: std.mem.Allocator, _: std.Io, _: *prof.Profiler) !void {
    for (ctx.paths) |path| {
        try ctx.snapshot.insert(alloc, path);
    }
}

fn collectPaths(
    io: Io,
    arena: std.mem.Allocator,
    gpa: std.mem.Allocator,
    out: *std.ArrayList([]const u8),
    abs_path: []const u8,
) !void {
    var dir = try Io.Dir.openDirAbsolute(io, abs_path, .{ .iterate = true });
    defer dir.close(io);

    var it = dir.iterateAssumeFirstIteration();
    while (try it.next(io)) |entry| {
        const child = try std.fs.path.join(arena, &.{ abs_path, entry.name });
        try out.append(gpa, child);

        if (entry.kind == .directory) {
            try collectPaths(io, arena, gpa, out, child);
        }
    }
}
