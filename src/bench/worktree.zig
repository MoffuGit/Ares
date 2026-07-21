const std = @import("std");
const Io = std.Io;
const testing = std.testing;
const Allocator = std.mem.Allocator;

const prof = @import("prof");
const test_build = @import("test_build");
const zlob = @import("zlob");

const App = @import("../app.zig");
const Entity = App.Entity;
const contants = @import("../contants.zig");
const MAX_PATH_LEN = contants.MAX_PATH_LEN;
const Worktree = @import("../worktree.zig");
const Snapshot = @import("../worktree/snapshot.zig");

pub fn observe(app: *App, worktree: Entity(Worktree), scanning: *bool) bool {
    scanning.* = worktree.read(app).scanning;
    return scanning.*;
}

test "Worktree Bench" {
    const gpa = std.heap.c_allocator;
    const io = testing.io;

    var app: App = undefined;
    try app.init(.{}, gpa, io);
    defer app.deinit();

    try verifyWorktree(&app, io);

    var bench: prof.Benchmark = undefined;
    bench.init(gpa, .{ .stop_ms = 20000, .name = "WORKTREE" });
    defer bench.deinit();

    const res = try bench.run(App, &app, gpa, io, initialWorktreeScan);
    try res.log(io, .stdout());
}

pub fn initialWorktreeScan(app: *App, _: std.mem.Allocator, io: std.Io, _: *prof.Profiler) !void {
    defer app.flush();

    const worktree: Entity(Worktree) = try .new(
        app,
        .{
            io,
            Worktree.Options{
                .abs_path = test_build.chromium_path,
            },
        },
    );
    defer worktree.drop();

    var scanning = true;

    _ = try app.observe(worktree, observe, .{&scanning});

    while (scanning) {
        app.flush();
    }
}

fn verifyWorktree(app: *App, io: Io) !void {
    const worktree: Entity(Worktree) = try .new(
        app,
        .{ io, Worktree.Options{ .abs_path = test_build.chromium_path } },
    );
    defer worktree.drop();

    var scanning = true;

    _ = try app.observe(worktree, observe, .{&scanning});

    while (scanning) {
        app.flush();
    }

    app.flush();

    var arena = std.heap.ArenaAllocator.init(app.gpa);
    defer arena.deinit();
    const alloc = arena.allocator();

    const snap = worktree.read(app).snapshot;

    var zlob_res = try zlob.walk.collect(alloc, test_build.chromium_path, .{
        .include_hidden = false,
        .respect_git = true,
        .report_dirs = true,
    });
    defer zlob_res.deinit();

    var zlob_set = std.StringHashMap(void).init(alloc);
    defer zlob_set.deinit();
    for (zlob_res.entries) |e| {
        try zlob_set.put(try alloc.dupe(u8, e.relativePath()), {});
    }

    const root_name = snap.root_name;
    const prefix_len = root_name.len + 1;
    var ody_set = std.StringHashMap(void).init(alloc);
    defer ody_set.deinit();

    var it = snap.entries.iter();
    while (it.next()) |kv| {
        const entry = kv.value;
        if (entry.meta.hidden or entry.meta.ignored) continue;

        var buf: [MAX_PATH_LEN]u8 = undefined;
        const written = entry.path.write(&buf);
        const full = buf[0..written];

        if (full.len == root_name.len and std.mem.eql(u8, full, root_name)) continue;

        if (full.len < prefix_len or full[root_name.len] != '/') {
            std.debug.print("verifyWorktreeScan: unexpected path shape: '{s}'\n", .{full});
            return error.WorktreeSnapshotMismatch;
        }
        const rel = full[prefix_len..];
        try ody_set.put(try alloc.dupe(u8, rel), {});
    }

    const ody_count = ody_set.count();
    const zlob_count = zlob_set.count();

    if (ody_count == zlob_count) {
        var zit = zlob_set.iterator();
        while (zit.next()) |e| {
            if (!ody_set.contains(e.key_ptr.*)) {
                std.debug.print(
                    "\n=== WORKTREE SNAPSHOT MISMATCH (same count, differing entries) ===\n",
                    .{},
                );
                std.debug.print("  zlob has '{s}' but odyssey does not\n", .{e.key_ptr.*});
                printFirstDivergence(&ody_set, &zlob_set);
                std.debug.print("====================================================================\n", .{});
                return error.WorktreeSnapshotMismatch;
            }
        }

        std.debug.print("====================================================================\n", .{});
        std.debug.print(
            "WORKTREE SCAN VERIFIED [{}]\n",
            .{ody_count},
        );

        return;
    }

    std.debug.print("\n=== WORKTREE SNAPSHOT MISMATCH ===\n", .{});
    std.debug.print("odyssey visible entries: {d}\n", .{ody_count});
    std.debug.print("zlob    visible entries: {d}\n", .{zlob_count});
    printFirstDivergence(&ody_set, &zlob_set);
    std.debug.print("===================================\n", .{});
    return error.WorktreeSnapshotMismatch;
}

fn printFirstDivergence(ody_set: *const std.StringHashMap(void), zlob_set: *const std.StringHashMap(void)) void {
    const cap: usize = 50;
    var only_ody: usize = 0;
    var oit = ody_set.iterator();
    while (oit.next()) |e| {
        if (!zlob_set.contains(e.key_ptr.*)) {
            if (only_ody < cap) std.debug.print("  only odyssey: {s}\n", .{e.key_ptr.*});
            only_ody += 1;
        }
    }
    var only_zlob: usize = 0;
    var zit = zlob_set.iterator();
    while (zit.next()) |e| {
        if (!ody_set.contains(e.key_ptr.*)) {
            if (only_zlob < cap) std.debug.print("  only zlob   : {s}\n", .{e.key_ptr.*});
            only_zlob += 1;
        }
    }
    std.debug.print("  total only odyssey: {d}\n", .{only_ody});
    std.debug.print("  total only zlob   : {d}\n", .{only_zlob});
}
