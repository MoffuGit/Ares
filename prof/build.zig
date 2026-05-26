const std = @import("std");
const prof = @import("mod.zig");

pub const ProfileLevel = prof.ProfileLevel;

pub const Options = struct {
    level: ProfileLevel,
    bench: bool = false,
};

pub fn option(b: *std.Build) ?ProfileLevel {
    return b.option(
        ProfileLevel,
        "profile",
        "Profiling level: none, general, or deep. Tests always use none; bench defaults to general.",
    );
}

pub fn module(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    options: Options,
) *std.Build.Module {
    const build_options = b.addOptions();

    var level = options.level;
    if (options.bench and level == .none) level = .general;

    build_options.addOption([]const u8, "profile_level", @tagName(level));
    build_options.addOption(bool, "bench", options.bench);

    const prof_mod = b.createModule(.{
        .root_source_file = b.path("prof/mod.zig"),
        .target = target,
        .optimize = optimize,
    });
    prof_mod.addOptions("prof_build", build_options);

    return prof_mod;
}
