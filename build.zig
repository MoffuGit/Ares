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

    // ── macOS App (zig build mac) ──
    buildMacApp(b, optimize);

    const vaxis_dep = b.dependency("vaxis", .{ .target = target, .optimize = optimize });
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
    b.installArtifact(tui_lib);

    const tui_lib_step = b.step("tui-lib", "Build tui lib and run the opentui application");
    tui_lib_step.dependOn(b.getInstallStep());
    tui_lib_step.dependOn(&tui_lib.step);

    const desktop = b.addSystemCommand(&.{ "bun", "run", "dev:hmr" });
    desktop.setCwd(b.path("packages/app/desktop"));

    const desktop_step = b.step("desktop", "Build desktop lib and run the Electrobun application");
    desktop.step.dependOn(b.getInstallStep());
    desktop_step.dependOn(&desktop.step);
    desktop.step.dependOn(&lib.step);

    const tui = b.addSystemCommand(&.{ "bun", "run", "dev" });
    tui.setCwd(b.path("packages/app/tui"));

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

fn buildMacApp(b: *std.Build, optimize: std.builtin.OptimizeMode) void {
    const aarch64_target = b.resolveTargetQuery(.{ .cpu_arch = .aarch64, .os_tag = .macos });
    const x86_64_target = b.resolveTargetQuery(.{ .cpu_arch = .x86_64, .os_tag = .macos });

    const aarch64_lib = buildMacStaticLib(b, aarch64_target, optimize);
    const x86_64_lib = buildMacStaticLib(b, x86_64_target, optimize);

    // lipo: create universal binary
    const lipo = b.addSystemCommand(&.{ "lipo", "-create" });
    lipo.addArtifactArg(aarch64_lib);
    lipo.addArtifactArg(x86_64_lib);
    lipo.addArg("-output");
    const universal_lib = lipo.addOutputFileArg("libares.a");

    // remove old xcframework (xcodebuild fails if it exists)
    const rm = b.addSystemCommand(&.{ "rm", "-rf", "packages/app/macos/AresKit.xcframework" });
    rm.setCwd(b.path("."));

    // create xcframework
    const xcframework = b.addSystemCommand(&.{ "xcodebuild", "-create-xcframework" });
    xcframework.addArg("-library");
    xcframework.addFileArg(universal_lib);
    xcframework.addArg("-headers");
    xcframework.addDirectoryArg(b.path("include"));
    xcframework.addArgs(&.{ "-output", "packages/app/macos/AresKit.xcframework" });
    xcframework.setCwd(b.path("."));
    xcframework.step.dependOn(&rm.step);

    // regenerate xcode project
    const xcodegen = b.addSystemCommand(&.{ "xcodegen", "generate" });
    xcodegen.setCwd(b.path("packages/app/macos"));
    xcodegen.step.dependOn(&xcframework.step);

    const mac_step = b.step("mac", "Build XCFramework and open the macOS Xcode project");
    mac_step.dependOn(&xcodegen.step);
}

fn buildMacStaticLib(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Step.Compile {
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
        .name = "ares",
        .root_module = mod,
        .linkage = .static,
    });
    lib.bundle_compiler_rt = true;
    lib.linkLibC();

    return lib;
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
