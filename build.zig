const std = @import("std");

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
        .root_source_file = b.path("src/core/mod.zig"),
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

    const desktop = b.addSystemCommand(&.{ "bun", "run", "dev:hmr" });
    desktop.setCwd(b.path("src/desktop"));

    const desktop_step = b.step("desktop", "Build desktop lib and run the Electrobun application");
    desktop.step.dependOn(b.getInstallStep());
    desktop_step.dependOn(&desktop.step);
    desktop.step.dependOn(&lib.step);

    const tui = b.addSystemCommand(&.{ "bun", "run", "dev" });
    tui.setCwd(b.path("src/tui"));

    const tui_step = b.step("tui", "Build tui lib and run the opentui application");
    tui_step.dependOn(b.getInstallStep());
    tui_step.dependOn(&tui.step);
    tui_step.dependOn(&lib.step);

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
}
