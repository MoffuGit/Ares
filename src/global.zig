const std = @import("std");
const builtin = @import("builtin");
const Settings = @import("settings/mod.zig");
const Allocator = std.mem.Allocator;

pub const xev = @import("xev").Dynamic;

pub var settings: *Settings = undefined;

pub fn init(alloc: Allocator) !void {
    settings = try Settings.create(alloc);
}

pub fn deinit() void {
    settings.destroy();
}
