const std = @import("std");
const prof = @import("prof/mod.zig");

const ProfileLevel = prof.ProfileLevel;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const requested = b.option(
        ProfileLevel,
        "profile",
        "Profiling level: none, general, or deep. Tests always use none; bench defaults to general.",
    );

    // exe: any level, default none.
    const exe = b.addExecutable(.{
        .name = "Odyssey",
        .root_module = rootModule(b, target, optimize, "src/main.zig", requested orelse .none, false),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Run the app").dependOn(&run_cmd.step);

    const clone_chromium = cloneChromiumStep(b);

    const exe_tests = b.addTest(.{
        .root_module = rootModule(b, target, optimize, "src/main.zig", .none, false),
    });
    exe_tests.step.dependOn(clone_chromium);
    b.step("test", "Run tests").dependOn(&b.addRunArtifact(exe_tests).step);

    const bench_level: ProfileLevel = switch (requested orelse .general) {
        .none, .general => .general,
        .deep => .deep,
    };
    const bench_tests = b.addTest(.{
        .root_module = rootModule(b, target, optimize, "src/bench.zig", bench_level, true),
    });

    bench_tests.step.dependOn(clone_chromium);
    const run_bench = b.addRunArtifact(bench_tests);
    run_bench.argv.shrinkRetainingCapacity(1);
    run_bench.stdio = .inherit;
    b.step("bench", "Run benchmarks").dependOn(&run_bench.step);
}

fn rootModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    root_source: []const u8,
    level: ProfileLevel,
    bench_enabled: bool,
) *std.Build.Module {
    const options = b.addOptions();
    options.addOption([]const u8, "profile_level", @tagName(level));
    options.addOption(bool, "bench_enabled", bench_enabled);

    const prof_mod = b.createModule(.{
        .root_source_file = b.path("prof/mod.zig"),
        .target = target,
        .optimize = optimize,
    });
    prof_mod.addOptions("prof_build", options);

    return b.createModule(.{
        .root_source_file = b.path(root_source),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "prof", .module = prof_mod }},
    });
}

const chromium_dir = "testdata/chromium";
const chromium_url = "https://github.com/chromium/chromium.git";

fn cloneChromiumStep(b: *std.Build) *std.Build.Step {
    const step = b.allocator.create(std.Build.Step) catch @panic("OOM");
    step.* = std.Build.Step.init(.{
        .id = .custom,
        .name = "clone chromium",
        .owner = b,
        .makeFn = cloneChromiumMake,
    });
    return step;
}

fn cloneChromiumMake(step: *std.Build.Step, opts: std.Build.Step.MakeOptions) anyerror!void {
    const b = step.owner;
    const io = b.graph.io;
    const dest = b.pathFromRoot(chromium_dir);
    const git_dir = b.pathJoin(&.{ dest, ".git" });

    if (std.Io.Dir.accessAbsolute(io, git_dir, .{})) |_| return else |_| {}

    std.Io.Dir.cwd().createDirPath(io, b.pathFromRoot("testdata")) catch |e|
        return step.fail("unable to create testdata dir: {s}", .{@errorName(e)});

    var node = opts.progress_node.start("git clone chromium", 0);
    defer node.end();

    var child = try std.process.spawn(io, .{
        .argv = &.{
            "git",                "clone",
            "--depth",            "1",
            "--filter=blob:none", chromium_url,
            dest,
        },
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .pipe,
    });

    const term = child.wait(io) catch |e|
        return step.fail("failed to spawn git: {s}", .{@errorName(e)});

    switch (term) {
        .exited => |code| if (code != 0)
            return step.fail("git clone exited with code {d}", .{code}),
        else => return step.fail("git clone terminated unexpectedly", .{}),
    }
}
