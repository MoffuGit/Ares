const std = @import("std");
const build_options = @import("prof_build");
const prof = @import("prof.zig");
const time = @import("time.zig");
const tripwire = @import("tripwire.zig");

pub const configured_level: ProfileLevel = std.meta.stringToEnum(ProfileLevel, build_options.profile_level) orelse
    @compileError("invalid prof_build.profile_level");

pub const bench: bool = build_options.bench;

pub const ProfileLevel = prof.ProfileLevel;

pub const Profiler = prof.Profiler(configured_level);
pub const Zone = prof.Zone(configured_level);
pub const Benchmark = @import("bench.zig");
pub const Sample = prof.Sample(configured_level);

pub var profiler: Profiler = undefined;
