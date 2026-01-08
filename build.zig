const std = @import("std");
const XCFrameworkStep = @import("src/build/CXFramerworkStep.zig");
const MetallibStep = @import("src/build/MetallibStep.zig");
const Step = std.Build.Step;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{ .name = "ares", .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    b.installArtifact(exe);
    b.default_step.dependOn(&exe.step);

    const xev = b.dependency("libxev", .{ .target = target, .optimize = optimize });

    exe.root_module.addImport("xev", xev.module("xev"));

    const test_exe: *Step.Compile = test_exe: {
        const test_filter = b.option(
            []const u8,
            "test-filter",
            "Filter for test",
        );
        const test_exe = b.addTest(.{
            .name = "ares-test",
            .filters = if (test_filter) |filter| &.{filter} else &.{},
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        switch (target.result.os.tag) {
            .linux, .macos => test_exe.linkLibC(),
            else => {},
        }
        break :test_exe test_exe;
    };

    test_exe.root_module.addImport("xev", xev.module("xev"));

    // "test" Step
    {
        const tests_run = b.addRunArtifact(test_exe);
        const test_step = b.step("test", "Run tests");
        test_step.dependOn(&tests_run.step);
    }

    const lib = b.addLibrary(.{
        .name = "Ares",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main_c.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    lib.root_module.addImport("objc", b.dependency("zig_objc", .{
        .target = target,
        .optimize = optimize,
    }).module("objc"));

    lib.root_module.addImport("macos", b.dependency("macos", .{
        .target = target,
        .optimize = optimize,
    }).module("macos"));

    lib.root_module.addImport("xev", xev.module("xev"));

    lib.bundle_compiler_rt = true;
    lib.linkLibC();
    b.default_step.dependOn(&lib.step);
    b.installArtifact(lib);

    const xcframework = XCFrameworkStep.create(b, .{
        .name = "AresKit",
        .out_path = "ares/AresKit.xcframework",
        .libraries = &.{.{ .library = lib.getEmittedBin(), .headers = b.path("include"), .dsym = null }},
    });
    xcframework.step.dependOn(&lib.step);
    b.default_step.dependOn(xcframework.step);

    const metallib = MetallibStep.create(b, .{
        .name = "Ares",
        .sources = &.{b.path("src/renderer/shaders/shaders.metal")},
    });
    lib.step.dependOn(metallib.?.step);
    lib.root_module.addAnonymousImport("ares_metallib", .{
        .root_source_file = metallib.?.output,
    });
}
