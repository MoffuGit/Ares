const std = @import("std");
const prof = @import("prof/mod.zig");

const ProfileLevel = prof.ProfileLevel;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const requested_profile_level = b.option(
        ProfileLevel,
        "profile",
        "Profiling level: none, general, or deep. Bench defaults to general when unset.",
    );
    const normal_profile_level = requested_profile_level orelse .none;
    const bench_profile_level = .general;

    const normal_options = profOptions(b, normal_profile_level, false);
    const prof_mod = b.createModule(.{
        .root_source_file = b.path("prof/mod.zig"),
        .target = target,
        .optimize = optimize,
    });
    prof_mod.addOptions("prof_build", normal_options);

    const exe = b.addExecutable(.{
        .name = "Odyssey",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addOptions("prof_build", normal_options);

    b.installArtifact(exe);
    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);

    const bench_options = profOptions(b, bench_profile_level, true);
    const bench_prof_mod = b.createModule(.{
        .root_source_file = b.path("prof/mod.zig"),
        .target = target,
        .optimize = optimize,
    });
    bench_prof_mod.addOptions("prof_build", bench_options);

    const bench_mod = b.createModule(.{
        .root_source_file = b.path("src/bench.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "prof", .module = bench_prof_mod },
        },
    });
    bench_mod.addOptions("prof_build", bench_options);

    const bench_tests = b.addTest(.{
        .root_module = bench_mod,
    });

    const run_bench_tests = b.addRunArtifact(bench_tests);
    run_bench_tests.argv.shrinkRetainingCapacity(1);
    run_bench_tests.stdio = .inherit;

    const bench_step = b.step("bench", "Run benchmarks");
    bench_step.dependOn(&run_bench_tests.step);
}

fn profOptions(
    b: *std.Build,
    profile_level: ProfileLevel,
    bench_enabled: bool,
) *std.Build.Step.Options {
    const options = b.addOptions();
    options.addOption([]const u8, "profile_level", @tagName(profile_level));
    options.addOption(bool, "bench_enabled", bench_enabled);
    return options;
}
