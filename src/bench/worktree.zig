const std = @import("std");
const Io = std.Io;
const testing = std.testing;
const prof = @import("prof");
const test_build = @import("test_build");
const Worktree = @import("../worktree.zig");
const App = @import("../app.zig");
const Entity = App.Entity;
const zlob = @import("zlob");

const WorktreeScanObserver = struct {
    scanning: bool,

    pub fn init(self: *@This(), _: App.Context(@This())) !void {
        self.* = .{ .scanning = true };
    }

    pub fn observe(self: *@This(), worktree: Entity(Worktree), ctx: App.Context(@This())) void {
        self.scanning = worktree.read(ctx.app).scanning;
    }
};

var expected: usize = 0;

test "Bench Worktree" {
    const gpa = std.heap.c_allocator;
    const io = testing.io;

    var app: App = undefined;
    try app.init(.{}, gpa, io);
    defer app.deinit();

    var bench: prof.Benchmark = undefined;
    bench.init(gpa, .{ .stop_ms = 20000, .name = "WORKTREE" });
    defer bench.deinit();

    var zlob_res = try zlob.walk.collect(gpa, test_build.chromium_path, .{});
    defer zlob_res.deinit();
    expected = zlob_res.entries.len;

    const res = try bench.run(App, &app, gpa, io, initialWorktreeScan);
    try res.log(io, .stdout());
}

pub fn initialWorktreeScan(app: *App, _: std.mem.Allocator, io: std.Io, _: *prof.Profiler) !void {
    defer app.flush();

    const worktree: Entity(Worktree) = try .new(
        app,
        .{
            io,
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
}
