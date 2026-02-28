const std = @import("std");
const yoga_sources = @import("yoga.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const xev_dep = b.dependency("libxev", .{ .target = target, .optimize = optimize });

    const datastruct = b.createModule(.{
        .root_source_file = b.path("src/datastruct/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mod = b.createModule(.{
        .root_source_file = b.path("src/mod.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addImport("xev", xev_dep.module("xev"));
    mod.addImport("datastruct", datastruct);

    const lib = b.addLibrary(.{
        .name = "core",
        .root_module = mod,
        .linkage = .dynamic,
    });
    b.installArtifact(lib);

    const vaxis_dep = b.dependency("vaxis", .{ .target = target, .optimize = optimize });
    const yoga_lib = buildYogaLib(b, target, optimize);
    const yoga_mod = buildYogaModule(b, target, optimize);

    const tui_lib_mod = b.createModule(.{
        .root_source_file = b.path("src/tui/lib.zig"),
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
    b.installArtifact(tui_lib);

    const desktop = b.addSystemCommand(&.{ "bun", "run", "dev:hmr" });
    desktop.setCwd(b.path("packages/desktop"));

    const desktop_step = b.step("desktop", "Build desktop lib and run the Electrobun application");
    desktop.step.dependOn(b.getInstallStep());
    desktop_step.dependOn(&desktop.step);
    desktop.step.dependOn(&lib.step);

    const tui = b.addSystemCommand(&.{ "bun", "run", "dev" });
    tui.setCwd(b.path("packages/tui"));

    const tui_step = b.step("tui", "Build tui lib and run the opentui application");
    tui_step.dependOn(b.getInstallStep());
    tui_step.dependOn(&tui.step);
    tui_step.dependOn(&lib.step);
    tui.step.dependOn(&tui_lib.step);

    // // ── Tests ──
    const test_filter = b.option([]const u8, "test-filter", "Filter for tests");

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.addImport("xev", xev_dep.module("xev"));
    test_mod.addImport("datastruct", datastruct);

    const test_exe = b.addTest(.{
        .name = "ares-test",
        .root_module = test_mod,
        .filters = if (test_filter) |f| &.{f} else &.{},
    });

    const test_run = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&test_run.step);

    const bun_test = b.addSystemCommand(&.{ "bun", "test" });
    bun_test.setCwd(b.path("packages/core"));
    bun_test.step.dependOn(b.getInstallStep());
    test_step.dependOn(&bun_test.step);
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
