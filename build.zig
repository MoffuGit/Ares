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

    const exe = b.addExecutable(.{
        .name = "Odyssey",
        .root_module = rootModule(b, target, optimize, "src/main.zig", requested orelse .none, false),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Run the app").dependOn(&run_cmd.step);

    const exe_tests = b.addTest(.{
        .root_module = rootModule(b, target, optimize, "src/test.zig", .none, false),
    });
    b.step("test", "Run tests").dependOn(&b.addRunArtifact(exe_tests).step);

    const bench_level: ProfileLevel = switch (requested orelse .general) {
        .none, .general => .general,
        .deep => .deep,
    };
    const bench_tests = b.addTest(.{
        .root_module = rootModule(b, target, optimize, "src/bench.zig", bench_level, true),
    });
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
