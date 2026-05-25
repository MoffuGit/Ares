const std = @import("std");
const prof = @import("prof/build.zig");
const @"test" = @import("test/build.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const requested = prof.option(b);
    const test_opts = @"test".options(b);

    const exe = b.addExecutable(.{
        .name = "Odyssey",
        .root_module = rootModule(
            b,
            target,
            optimize,
            "src/main.zig",
            .{ .level = requested orelse .none },
            null,
        ),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    b.step("run", "Run the app").dependOn(&run_cmd.step);

    const clone_chromium = @"test".cloneChromiumStep(b);
    const bench_filter = b.option([]const u8, "bench-filter", "Only run benchmarks whose test name contains this text");

    const exe_tests = b.addTest(.{
        .root_module = rootModule(
            b,
            target,
            optimize,
            "src/test.zig",
            .{ .level = requested orelse .none },
            test_opts,
        ),
    });
    exe_tests.step.dependOn(clone_chromium);
    b.step("test", "Run tests").dependOn(&b.addRunArtifact(exe_tests).step);

    const bench_tests = b.addTest(.{
        .root_module = rootModule(b, target, optimize, "src/bench.zig", .{
            .level = requested orelse .general,
            .bench = true,
        }, test_opts),
        .filters = if (bench_filter) |filter| &.{filter} else &.{},
    });

    const bench_artifact = b.addInstallArtifact(
        bench_tests,
        .{ .dest_dir = .{ .override = .{ .custom = "benchs" } } },
    );

    const install_bench_step = b.step("install_bench", "Create bench binaries for debugging");
    install_bench_step.dependOn(&bench_artifact.step);

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
    prof_opts: prof.Options,
    test_opts: ?@"test".Options,
) *std.Build.Module {
    const prof_mod = prof.module(b, target, optimize, prof_opts);

    const mod = b.createModule(.{
        .root_source_file = b.path(root_source),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "prof", .module = prof_mod }},
    });
    if (test_opts) |opts| @"test".addOptions(mod, b, opts);
    return mod;
}
