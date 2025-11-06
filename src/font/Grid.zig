const Grid = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Atlas = @import("Atlas.zig");
const CodePointResolver = @import("CodePointResolver.zig");
const facepkg = @import("face/mod.zig");
const Face = facepkg.Face;
const embedpkg = @import("embedded/mod.zig");
const Metrics = facepkg.Metrics;
const sizepkg = @import("../size.zig");

atlas_grayscale: Atlas,
resolver: CodePointResolver,
lock: std.Thread.RwLock = .{},
metrics: Metrics,
// glyphs: void,
// codepoints: void,

pub fn init(alloc: Allocator, opts: facepkg.Options) !Grid {
    var atlas_grayscale = try Atlas.init(alloc, 512, .grayscale);
    errdefer atlas_grayscale.deinit(alloc);

    var grid = Grid{ .atlas_grayscale = atlas_grayscale, .resolver = .{
        .face = try Face.init(embedpkg.JetBrainsMono, opts),
    }, .metrics = undefined };

    try grid.reloadMetrics();

    return grid;
}

fn reloadMetrics(self: *Grid) !void {
    const face = &self.resolver.face;

    self.metrics = Metrics.calc(face.getMetrics());
}

pub fn cellSize(self: *Grid) sizepkg.CellSize {
    return .{ .width = self.metrics.cell_width, .height = self.metrics.cell_height };
}

pub fn deinit(self: *Grid, alloc: Allocator) void {
    self.atlas_grayscale.deinit(alloc);
    self.resolver.deinit();
}

pub fn renderCodepoint(self: *Grid, alloc: Allocator, cp: u32) !?void {
    _ = alloc;
    const index = self.resolver.face.glyphIndex(cp) orelse return null;

    std.log.debug("index: {}", .{index});
}
