const std = @import("std");
const yoga_sources = @import("yoga.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const vaxis_dep = b.dependency("vaxis", .{ .target = target, .optimize = optimize });
    const xev_dep = b.dependency("libxev", .{ .target = target, .optimize = optimize });

    const yoga_lib = buildYogaLib(b, target, optimize);
    const yoga_mod = buildYogaModule(b, target, optimize);

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addImport("yoga", yoga_mod);
    exe_mod.addImport("vaxis", vaxis_dep.module("vaxis"));
    exe_mod.addImport("xev", xev_dep.module("xev"));

    const exe = b.addExecutable(.{ .name = "ares", .root_module = exe_mod });
    exe.step.dependOn(&yoga_lib.step);

    b.installArtifact(exe);
    b.installArtifact(yoga_lib);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);

    // Yoga test executable
    const yoga_test_mod = b.createModule(.{
        .root_source_file = b.path("src/yoga_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    yoga_test_mod.addImport("yoga", yoga_mod);
    yoga_test_mod.addImport("Style", b.createModule(.{
        .root_source_file = b.path("src/element/Style.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "yoga", .module = yoga_mod }},
    }));

    const yoga_test_exe = b.addExecutable(.{ .name = "yoga-test", .root_module = yoga_test_mod });
    yoga_test_exe.linkLibrary(yoga_lib);
    yoga_test_exe.step.dependOn(&yoga_lib.step);

    const yoga_test_run = b.addRunArtifact(yoga_test_exe);
    yoga_test_run.step.dependOn(b.getInstallStep());

    const yoga_test_step = b.step("yoga-test", "Run yoga layout test");
    yoga_test_step.dependOn(&yoga_test_run.step);

    const test_filter = b.option([]const u8, "test-filter", "Filter for tests");

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.addImport("vaxis", vaxis_dep.module("vaxis"));
    test_mod.addImport("xev", xev_dep.module("xev"));

    const test_exe = b.addTest(.{
        .name = "ares-test",
        .root_module = test_mod,
        .filters = if (test_filter) |f| &.{f} else &.{},
    });

    if (target.result.os.tag == .linux or target.result.os.tag == .macos) {
        test_exe.linkLibC();
    }

    const test_run = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&test_run.step);
}

fn buildYogaLib(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
    const yoga_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "yoga",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });

    yoga_lib.linkLibCpp();
    yoga_lib.addIncludePath(b.path("yoga"));

    for (yoga_sources.yoga_cpps) |src| {
        yoga_lib.addCSourceFile(.{
            .file = b.path(src),
            .flags = &.{"-std=c++20"},
        });
    }

    ensureYogaCloned(b, &yoga_lib.step);

    return yoga_lib;
}

fn buildYogaModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("yoga/yoga/yoga.h"),
        .target = target,
        .optimize = optimize,
    });
    translate_c.addIncludePath(b.path("yoga"));

    return b.createModule(.{
        .root_source_file = translate_c.getOutput(),
        .target = target,
        .optimize = optimize,
    });
}

fn ensureYogaCloned(b: *std.Build, dependent_step: *std.Build.Step) void {
    const cwd = std.fs.cwd();
    cwd.access("yoga", .{}) catch |err| {
        if (err == error.FileNotFound) {
            const git_clone = b.addSystemCommand(&.{
                "git",                                  "clone",
                "https://github.com/facebook/yoga.git", "--depth=1",
            });
            dependent_step.dependOn(&git_clone.step);
        }
    };
}
