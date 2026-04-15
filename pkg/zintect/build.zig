const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const cargo_build = b.addSystemCommand(&.{
        "cargo",
        "build",
        "--release",
        "--quiet",
        "--manifest-path",
    });
    cargo_build.addFileArg(b.path("../../zintect/Cargo.toml"));

    const module = b.addModule("zintect", .{
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addIncludePath(b.path("../../zintect/include"));
    module.addObjectFile(.{ .cwd_relative = "../../zintect/target/release/libzintect.a" });

    const lib = b.addLibrary(.{
        .name = "zintect",
        .root_module = module,
        .linkage = .static,
    });
    lib.step.dependOn(&cargo_build.step);

    const tests = b.addTest(.{
        .name = "test-zintect",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    tests.root_module.addIncludePath(b.path("../../zintect/include"));
    tests.root_module.addObjectFile(.{ .cwd_relative = "../../zintect/target/release/libzintect.a" });
    tests.step.dependOn(&cargo_build.step);

    const run_tests = b.addRunArtifact(tests);

    b.installArtifact(lib);

    const test_step = b.step("test", "Run zintect Zig tests");
    test_step.dependOn(&run_tests.step);
}
