const std = @import("std");
const build_options = @import("prof_build");
const prof = @import("prof.zig");
const time = @import("time.zig");

pub const configured_level: ProfileLevel = std.meta.stringToEnum(ProfileLevel, build_options.profile_level) orelse
    @compileError("invalid prof_build.profile_level");

pub const bench_enabled: bool = build_options.bench_enabled;

pub const ProfileLevel = prof.ProfileLevel;

pub const Profiler = prof.Profiler(.{ .level = configured_level });
pub const Zone = prof.Zone(Profiler);
pub const Benchmark = @import("bench.zig");
