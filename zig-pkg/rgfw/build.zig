const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const translate_c = b.addTranslateC(.{
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("RGFW.h"),
    });

    const c_mod = translate_c.createModule();

    c_mod.addCSourceFile(.{
        .file = b.path("RGFW.c"),
    });
    c_mod.linkFramework("Cocoa", .{});
    c_mod.linkFramework("CoreVideo", .{});
    c_mod.linkFramework("IOKit", .{});

    _ = b.addModule(
        "rgfw",
        .{
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/root.zig"),
            .imports = &.{
                .{ .name = "c", .module = c_mod },
            },
        },
    );
}
