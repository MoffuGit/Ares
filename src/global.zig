const std = @import("std");

const Settings = @import("settings/mod.zig");
const Allocator = std.mem.Allocator;
const Context = @import("app/mod.zig").Context;

pub const xev = @import("xev").Dynamic;

pub var settings: *Settings = undefined;

pub fn init(alloc: Allocator, context: *Context) !void {
    settings = try Settings.create(alloc, context);
}

pub fn deinit() void {
    settings.destroy();
}
