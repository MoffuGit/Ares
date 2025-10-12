const std = @import("std");
const XCFrameworkStep = @import("CXFramerworkStep.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addLibrary(.{
        .name = "Ares",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

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
}
