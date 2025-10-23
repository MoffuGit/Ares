const std = @import("std");
const XCFrameworkStep = @import("src/build/CXFramerworkStep.zig");

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
