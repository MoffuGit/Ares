const Collection = @This();

const std = @import("std");
const facepkg = @import("face/mod.zig");
const fontpkg = @import("mod.zig");
const sizepkg = @import("../size.zig");

const Allocator = std.mem.Allocator;
const Metrics = facepkg.Metrics;
const Face = facepkg.Face;
const Style = fontpkg.Style;

const StyledArray = std.EnumArray(Style, Face);

metrics: Metrics = undefined,
metric_modifiers: Metrics.ModifierSet = .{},
faces: StyledArray,

pub fn init() Collection {
    return .{ .faces = .initUndefined() };
}

pub fn add(self: *Collection, face: Face, style: Style) void {
    const old = self.faces.getPtr(style);
    old.* = face;
}

pub fn reloadMetrics(self: *Collection) void {
    const face = self.faces.getPtr(.regular);

    var metrics = Metrics.calc(face.getMetrics());

    metrics.apply(self.metric_modifiers);

    self.metrics = metrics;
}

pub fn deinit(self: *Collection, alloc: Allocator) void {
    var iter = self.faces.iterator();
    while (iter.next()) |entry| {
        entry.value.deinit();
    }

    self.metric_modifiers.deinit(alloc);
}
