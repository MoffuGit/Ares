const Grid = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Atlas = @import("Atlas.zig");
const CodePointResolver = @import("CodePointResolver.zig");
const Shaper = @import("Shaper.zig");
const fontpkg = @import("../font/mod.zig");
const facepkg = @import("face/mod.zig");
const Face = facepkg.Face;
const embedpkg = @import("embedded/mod.zig");
const Metrics = facepkg.Metrics;
const sizepkg = @import("../size.zig");

atlas_grayscale: Atlas,
resolver: CodePointResolver,
shaper: Shaper,
lock: std.Thread.RwLock = .{},
metrics: Metrics,
metric_modifiers: Metrics.ModifierSet = .{},

glyphs: std.AutoHashMap(u32, fontpkg.Glyph),
codepoints: std.AutoHashMap(u32, u32),

pub fn init(alloc: Allocator, opts: facepkg.Options) !Grid {
    var atlas_grayscale = try Atlas.init(alloc, 512, .grayscale);
    errdefer atlas_grayscale.deinit(alloc);

    var grid = Grid{
        .atlas_grayscale = atlas_grayscale,
        .resolver = .{ .face = try Face.init(embedpkg.JetBrainsMono, opts) },
        .shaper = try Shaper.init(alloc),
        .metrics = undefined,
        .glyphs = std.AutoHashMap(u32, fontpkg.Glyph).init(alloc),
        .codepoints = std.AutoHashMap(u32, u32).init(alloc),
    };
    errdefer grid.shaper.deinit();
    errdefer grid.glyphs.deinit();
    errdefer grid.codepoints.deinit();

    try grid.metric_modifiers.put(alloc, .cell_width, .{ .absolute = -1 });

    try grid.reloadMetrics();

    return grid;
}

fn reloadMetrics(self: *Grid) !void {
    const face = &self.resolver.face;

    var metrics = Metrics.calc(face.getMetrics());

    metrics.apply(self.metric_modifiers);

    self.metrics = metrics;
}

pub fn cellSize(self: *Grid) sizepkg.CellSize {
    return .{ .width = self.metrics.cell_width, .height = self.metrics.cell_height };
}

pub fn deinit(self: *Grid, alloc: Allocator) void {
    self.atlas_grayscale.deinit(alloc);
    self.resolver.deinit();
    self.shaper.deinit();
    self.glyphs.deinit();
    self.metric_modifiers.deinit(alloc);
    self.codepoints.deinit();
}

pub fn shapeRow(self: *Grid, alloc: Allocator, codepoints: []const u32) ![]const Shaper.ShapedGlyph {
    return self.shaper.shapeRow(alloc, &self.resolver.face, self.metrics, codepoints);
}

pub fn renderCodepoint(self: *Grid, alloc: Allocator, cp: u32) !?fontpkg.Glyph {
    const index = try self.getIndex(cp) orelse return null;

    return try self.renderGlyph(alloc, index);
}

pub fn getIndex(self: *Grid, cp: u32) !?u32 {
    {
        self.lock.lockShared();
        defer self.lock.unlockShared();

        if (self.codepoints.get(cp)) |cached_index| {
            return cached_index;
        }
    }
    self.lock.lock();
    self.lock.unlock();

    const index = self.resolver.face.glyphIndex(cp) orelse return null;

    try self.codepoints.put(cp, index);

    return index;
}

pub fn renderGlyph(self: *Grid, alloc: Allocator, index: u32) !fontpkg.Glyph {
    {
        self.lock.lockShared();
        defer self.lock.unlockShared();

        if (self.glyphs.get(index)) |cached_glyph| {
            return cached_glyph;
        }
    }

    self.lock.lock();
    defer self.lock.unlock();

    const atlas = &self.atlas_grayscale;

    const glyph = try self.resolver.face.renderGlyph(alloc, atlas, index, .{
        .grid_metrics = self.metrics,
    });
    try self.glyphs.put(index, glyph);

    return glyph;
}
