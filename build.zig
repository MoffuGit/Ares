const std = @import("std");
const Step = std.Build.Step;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const vaxis = b.dependency("vaxis", .{
        .target = target,
        .optimize = optimize,
    });

    const xev = b.dependency("libxev", .{ .target = target, .optimize = optimize });

    mod.addImport("vaxis", vaxis.module("vaxis"));
    mod.addImport("xev", xev.module("xev"));

    const exe = b.addExecutable(.{ .name = "ares", .root_module = mod });

    b.installArtifact(exe);
    b.default_step.dependOn(&exe.step);

    const test_exe: *Step.Compile = test_exe: {
        const test_filter = b.option(
            []const u8,
            "test-filter",
            "Filter for test",
        );

        const test_mod = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });

        test_mod.addImport("vaxis", vaxis.module("vaxis"));
        test_mod.addImport("xev", xev.module("xev"));

        const test_exe = b.addTest(.{
            .name = "ares-test",
            .filters = if (test_filter) |filter| &.{filter} else &.{},
            .root_module = test_mod,
        });
        switch (target.result.os.tag) {
            .linux, .macos => test_exe.linkLibC(),
            else => {},
        }
        break :test_exe test_exe;
    };

    {
        const tests_run = b.addRunArtifact(test_exe);
        const test_step = b.step("test", "Run tests");
        test_step.dependOn(&tests_run.step);
    }
}
