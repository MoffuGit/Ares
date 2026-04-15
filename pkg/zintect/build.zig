const std = @import("std");
const builtin = @import("builtin");
const apple_sdk = @import("apple_sdk");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("zintect", .{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .name = "zintect",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });
    lib.addIncludePath(b.path("../../zintect/include"));
    lib.addObjectFile(.{ .cwd_relative = "zintect/target/release/libzintect.a" });

    b.installArtifact(lib);

    module.addIncludePath(b.path("../../zintect/include"));
    module.addObjectFile(.{ .cwd_relative = "zintect/target/release/libzintect.a" });
}
