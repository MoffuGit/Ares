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
const Style = fontpkg.Style;

const CodepointKey = struct {
    style: Style,
    codepoint: u32,
};

atlas_grayscale: Atlas,
resolver: CodePointResolver,
shaper: Shaper,
lock: std.Thread.RwLock = .{},
metrics: Metrics,
metric_modifiers: Metrics.ModifierSet = .{},

glyphs: std.AutoHashMap(u32, fontpkg.Glyph),
codepoints: std.AutoHashMapUnmanaged(CodepointKey, u32) = .{},

pub fn init(alloc: Allocator, opts: facepkg.Options) !Grid {
    var atlas_grayscale = try Atlas.init(alloc, 512, .grayscale);
    errdefer atlas_grayscale.deinit(alloc);

    var grid = Grid{
        .atlas_grayscale = atlas_grayscale,
        .resolver = .{
            .face = try Face.init(embedpkg.GeistMono, opts),
            .fallback = try Face.init(embedpkg.JetBrainsMono, opts),
        },
        .shaper = try Shaper.init(alloc),
        .metrics = undefined,
        .glyphs = std.AutoHashMap(u32, fontpkg.Glyph).init(alloc),
    };
    errdefer grid.shaper.deinit();
    errdefer grid.glyphs.deinit();
    errdefer grid.codepoints.deinit(alloc);

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
    self.codepoints.deinit(alloc);
}

pub fn shapeRow(self: *Grid, alloc: Allocator, codepoints: []const u32) ![]const Shaper.ShapedGlyph {
    return self.shaper.shapeRow(alloc, &self.resolver.face, self.metrics, codepoints);
}

pub fn renderCodepoint(self: *Grid, alloc: Allocator, cp: u32, style: Style) !?fontpkg.Glyph {
    const index = try self.getIndex(alloc, cp, style) orelse return null;

    return try self.renderGlyph(alloc, index);
}

pub fn getIndex(self: *Grid, alloc: Allocator, cp: u32, style: Style) !?u32 {
    {
        self.lock.lockShared();
        defer self.lock.unlockShared();

        if (self.codepoints.get(.{ .codepoint = cp, .style = style })) |cached_index| {
            return cached_index;
        }
    }
    self.lock.lock();
    self.lock.unlock();

    if (self.resolver.face.glyphIndex(cp)) |index| {
        try self.codepoints.put(alloc, .{ .codepoint = cp, .style = style }, index);
        return index;
    }

    if (self.resolver.fallback) |*fb| {
        if (fb.glyphIndex(cp)) |index| {
            const tagged = index;
            try self.codepoints.put(alloc, .{ .codepoint = cp, .style = style }, tagged);
            return tagged;
        }
    }

    return null;
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
    const raw_index = index;

    const face = &self.resolver.face;
    const glyph = try face.renderGlyph(alloc, atlas, raw_index, .{
        .grid_metrics = self.metrics,
    });
    try self.glyphs.put(index, glyph);

    return glyph;
}
