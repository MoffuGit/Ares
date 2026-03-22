const std = @import("std");
const objc = @import("objc");
const global = @import("global.zig");
const MacAppearance = @import("./appearance/mac.zig");
const Allocator = std.mem.Allocator;

pub const Observer = MacAppearance.Observer;

const Appearance = @This();

alloc: Allocator,
observer: *Observer,

pub fn create(alloc: Allocator) !*Appearance {
    const appearance = try alloc.create(Appearance);
    errdefer alloc.destroy(appearance);

    const observer = try Observer.create(alloc);

    appearance.* = .{ .observer = observer, .alloc = alloc };

    return appearance;
}

pub fn destroy(self: *Appearance) void {
    self.observer.destroy();
    self.alloc.destroy(self);
}

pub fn isDark(_: *Appearance) bool {
    return MacAppearance.isDark();
}

pub fn setWindowTrafficLightsPosition(window_ptr: *anyopaque, x: f64, y_from_top: f64) bool {
    return MacAppearance.setWindowTrafficLightsPosition(window_ptr, x, y_from_top);
}
