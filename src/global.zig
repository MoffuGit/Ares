const std = @import("std");
const builtin = @import("builtin");
const Settings = @import("settings/mod.zig");
const Allocator = std.mem.Allocator;
const AppContext = @import("AppContext.zig");

pub const xev = @import("xev").Dynamic;

pub var settings: *Settings = undefined;

pub fn init(alloc: Allocator, context: *AppContext) !void {
    settings = try Settings.create(alloc, context);
}

pub fn deinit() void {
    settings.destroy();
}
