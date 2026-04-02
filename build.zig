const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const xev_dep = b.dependency("libxev", .{ .target = target, .optimize = optimize });
    const ghostty_dep = b.dependency("ghostty", .{ .target = target, .optimize = optimize });
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
    core_mod.addImport("ghostty-vt", ghostty_dep.module("ghostty-vt"));
    core_mod.addImport("xev", xev_dep.module("xev"));
    core_mod.addImport("datastruct", datastruct);
    core_mod.addImport("objc", objc_dep.module("objc"));

    core_mod.addImport("macos", b.dependency("macos", .{
        .target = target,
        .optimize = optimize,
    }).module("macos"));

    const core_lib = b.addLibrary(.{
        .name = "core",
        .root_module = core_mod,
        .linkage = .dynamic,
    });
    core_lib.linkFramework("Metal");
    core_lib.linkFramework("QuartzCore");
    const lib_install = b.addInstallArtifact(core_lib, .{});

    const core_step = b.step("core", "Build Core Lib");
    core_step.dependOn(&core_lib.step);
    core_step.dependOn(&lib_install.step);

    const metallib = MetallibStep.create(b, .{
        .name = "Ares",
        .sources = &.{b.path("core/renderer/shaders/shaders.metal")},
    });

    core_step.dependOn(metallib.?.step);
    core_mod.addAnonymousImport("ares_metallib", .{
        .root_source_file = metallib.?.output,
    });

    const desktop_bun = b.addSystemCommand(&.{ "bun", "run", "start" });
    desktop_bun.setCwd(b.path("packages/app/desktop"));

    const desktop_step = b.step("desktop", "Build desktop lib and run the Electrobun application");
    desktop_step.dependOn(core_step);
    desktop_step.dependOn(&desktop_bun.step);

    const test_filter = b.option([]const u8, "test-filter", "Filter for tests");

    const test_core = b.createModule(.{
        .root_source_file = b.path("core/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_core.addImport("macos", b.dependency("macos", .{
        .target = target,
        .optimize = optimize,
    }).module("macos"));
    core_step.dependOn(&core_lib.step);
    core_step.dependOn(&lib_install.step);

    test_core.addImport("xev", xev_dep.module("xev"));
    test_core.addImport("datastruct", datastruct);
    test_core.addImport("objc", objc_dep.module("objc"));

    const test_core_exe = b.addTest(.{
        .name = "test-core",
        .root_module = test_core,
        .filters = if (test_filter) |f| &.{f} else &.{},
    });

    const test_core_run = b.addRunArtifact(test_core_exe);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&test_core_run.step);

    const bun_core_test = b.addSystemCommand(&.{ "bun", "test" });
    bun_core_test.setCwd(b.path("packages/core"));
    bun_core_test.step.dependOn(&core_lib.step);
    bun_core_test.step.dependOn(&lib_install.step);

    test_step.dependOn(&bun_core_test.step);
}
/// A zig build step that compiles a set of ".metal" files into a
/// ".metallib" file.
const MetallibStep = @This();

const Step = std.Build.Step;
const RunStep = std.Build.Step.Run;
const LazyPath = std.Build.LazyPath;

pub const Options = struct {
    /// The name of the xcframework to create.
    name: []const u8,

    /// The Metal source files.
    sources: []const LazyPath,
};

step: *Step,
output: LazyPath,

pub fn create(b: *std.Build, opts: Options) ?*MetallibStep {
    const sdk = "macosx";
    const platform_version_arg = "-mmacos-version-min";

    const self = b.allocator.create(MetallibStep) catch @panic("OOM");

    const min_version = "10.14";

    const run_ir = RunStep.create(
        b,
        b.fmt("metal {s}", .{opts.name}),
    );
    run_ir.addArgs(&.{ "/usr/bin/xcrun", "-sdk", sdk, "metal", "-o" });
    const output_ir = run_ir.addOutputFileArg(b.fmt("{s}.ir", .{opts.name}));
    run_ir.addArgs(&.{"-c"});
    for (opts.sources) |source| run_ir.addFileArg(source);
    run_ir.addArgs(&.{b.fmt(
        "{s}={s}",
        .{ platform_version_arg, min_version },
    )});

    const run_lib = RunStep.create(
        b,
        b.fmt("metallib {s}", .{opts.name}),
    );
    run_lib.addArgs(&.{ "/usr/bin/xcrun", "-sdk", sdk, "metallib", "-o" });
    const output_lib = run_lib.addOutputFileArg(b.fmt("{s}.metallib", .{opts.name}));
    run_lib.addFileArg(output_ir);
    run_lib.step.dependOn(&run_ir.step);

    self.* = .{
        .step = &run_lib.step,
        .output = output_lib,
    };

    return self;
}
