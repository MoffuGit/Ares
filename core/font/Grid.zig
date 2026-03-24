const Grid = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Atlas = @import("Atlas.zig");
const CodePointResolver = @import("CodePointResolver.zig");
const fontpkg = @import("../font/mod.zig");
const facepkg = @import("face/mod.zig");
const Face = facepkg.Face;
const embedpkg = @import("embedded/mod.zig");
const Metrics = facepkg.Metrics;
const sizepkg = @import("../size.zig");

atlas_grayscale: Atlas,
resolver: CodePointResolver,
lock: std.Thread.RwLock = .{},
metrics: Metrics,
glyphs: std.AutoHashMap(u32, fontpkg.Glyph),
codepoints: std.AutoHashMap(u32, u32),

pub fn init(alloc: Allocator, opts: facepkg.Options) !Grid {
    var atlas_grayscale = try Atlas.init(alloc, 512, .grayscale);
    errdefer atlas_grayscale.deinit(alloc);

    var grid = Grid{
        .atlas_grayscale = atlas_grayscale,
        .resolver = .{ .face = try Face.init(embedpkg.JetBrainsMono, opts) },
        .metrics = undefined,
        .glyphs = std.AutoHashMap(u32, fontpkg.Glyph).init(alloc),
        .codepoints = std.AutoHashMap(u32, u32).init(alloc),
    };
    errdefer grid.glyphs.deinit();
    errdefer grid.codepoints.deinit();

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
    self.glyphs.deinit();
    self.codepoints.deinit();
}

pub fn renderCodepoint(self: *Grid, alloc: Allocator, cp: u32) !fontpkg.Glyph {
    if (self.codepoints.get(cp)) |cached_index| {
        return self.renderGlyph(alloc, cached_index);
    }

    const index = self.resolver.face.glyphIndex(cp) orelse return error.CpWithoutIndex;

    try self.codepoints.put(cp, index);

    return try self.renderGlyph(alloc, index);
}

pub fn renderGlyph(self: *Grid, alloc: Allocator, index: u32) !fontpkg.Glyph {
    if (self.glyphs.get(index)) |cached_glyph| {
        return cached_glyph;
    }

    const atlas = &self.atlas_grayscale;

    const glyph = try self.resolver.face.renderGlyph(alloc, atlas, index, .{
        .grid_metrics = self.metrics,
    });
    try self.glyphs.put(index, glyph);

    return glyph;
}
