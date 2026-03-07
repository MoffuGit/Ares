const std = @import("std");
const yoga_sources = @import("yoga.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const vaxis_dep = b.dependency("vaxis", .{ .target = target, .optimize = optimize });
    const xev_dep = b.dependency("libxev", .{ .target = target, .optimize = optimize });
    const objc_dep = b.dependency("zig_objc", .{
        .target = target,
        .optimize = optimize,
    });

    const datastruct = b.createModule(.{
        .root_source_file = b.path("datastruct/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    const core_mod = b.createModule(.{
        .root_source_file = b.path("core/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    core_mod.addImport("xev", xev_dep.module("xev"));
    core_mod.addImport("datastruct", datastruct);
    core_mod.addImport("objc", objc_dep.module("objc"));

    const core_lib = b.addLibrary(.{
        .name = "core",
        .root_module = core_mod,
        .linkage = .dynamic,
    });
    const lib_install = b.addInstallArtifact(core_lib, .{});

    const core_step = b.step("core", "Build Core Lib");
    core_step.dependOn(&core_lib.step);
    core_step.dependOn(&lib_install.step);

    const desktop_bun = b.addSystemCommand(&.{ "bun", "run", "dev:hmr" });
    desktop_bun.setCwd(b.path("packages/app/desktop"));

    const desktop_step = b.step("desktop", "Build desktop lib and run the Electrobun application");
    desktop_step.dependOn(&core_lib.step);
    desktop_step.dependOn(&lib_install.step);
    desktop_step.dependOn(&desktop_bun.step);

    const yoga_lib = buildYogaLib(b, target, optimize);
    const yoga_mod = buildYogaModule(b, target, optimize);

    const tui_lib_mod = b.createModule(.{
        .root_source_file = b.path("tui/lib.zig"),
        .target = target,
        .optimize = optimize,
    });
    tui_lib_mod.addImport("datastruct", datastruct);
    tui_lib_mod.addImport("xev", xev_dep.module("xev"));
    tui_lib_mod.addImport("vaxis", vaxis_dep.module("vaxis"));
    tui_lib_mod.addImport("yoga", yoga_mod);

    const tui_lib = b.addLibrary(.{
        .name = "tui",
        .root_module = tui_lib_mod,
        .linkage = .dynamic,
    });
    tui_lib.linkLibrary(yoga_lib);
    const tui_install = b.addInstallArtifact(tui_lib, .{});

    const tui_lib_step = b.step("tui-lib", "Build tui lib and run the opentui application");
    tui_lib_step.dependOn(&tui_lib.step);
    tui_lib_step.dependOn(&tui_install.step);

    const tui = b.addSystemCommand(&.{ "bun", "run", "dev" });
    tui.setCwd(b.path("packages/app/tui"));

    const tui_step = b.step("tui", "Build tui lib and run the opentui application");
    tui_step.dependOn(b.getInstallStep());
    tui_step.dependOn(&tui.step);
    tui_step.dependOn(&tui_lib.step);
    tui_step.dependOn(&tui_install.step);

    const test_filter = b.option([]const u8, "test-filter", "Filter for tests");

    const test_core = b.createModule(.{
        .root_source_file = b.path("core/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_core.addImport("xev", xev_dep.module("xev"));
    test_core.addImport("datastruct", datastruct);
    test_core.addImport("objc", objc_dep.module("objc"));

    const test_tui_core = b.createModule(.{
        .root_source_file = b.path("tui/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_tui_core.addImport("xev", xev_dep.module("xev"));
    test_tui_core.addImport("datastruct", datastruct);
    test_tui_core.addImport("yoga", yoga_mod);
    test_tui_core.addImport("vaxis", vaxis_dep.module("vaxis"));
    test_tui_core.linkLibrary(yoga_lib);

    const test_core_exe = b.addTest(.{
        .name = "test-core",
        .root_module = test_core,
        .filters = if (test_filter) |f| &.{f} else &.{},
    });

    const test_tui_core_exe = b.addTest(.{
        .name = "test-tui-core",
        .root_module = test_tui_core,
        .filters = if (test_filter) |f| &.{f} else &.{},
    });

    const test_core_run = b.addRunArtifact(test_core_exe);
    const test_tui_core_run = b.addRunArtifact(test_tui_core_exe);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&test_core_run.step);
    test_step.dependOn(&test_tui_core_run.step);

    const bun_core_test = b.addSystemCommand(&.{ "bun", "test" });
    bun_core_test.setCwd(b.path("packages/core"));
    bun_core_test.step.dependOn(&core_lib.step);
    bun_core_test.step.dependOn(&lib_install.step);

    const bun_tui_core_test = b.addSystemCommand(&.{ "bun", "test" });
    bun_tui_core_test.setCwd(b.path("packages/tui"));
    bun_tui_core_test.step.dependOn(&tui_lib.step);
    bun_tui_core_test.step.dependOn(&tui_install.step);

    test_step.dependOn(&bun_core_test.step);
    test_step.dependOn(&bun_tui_core_test.step);
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
