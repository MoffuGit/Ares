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
const Collection = @import("Collection.zig");

const CodepointKey = struct {
    style: Style,
    codepoint: u32,
};

const GlyphKey = struct {
    index: u32,
    style: Style,
};

atlas_grayscale: Atlas,
resolver: CodePointResolver,
shaper: Shaper,
lock: std.Thread.RwLock = .{},
metrics: Metrics = undefined,

glyphs: std.AutoHashMap(GlyphKey, fontpkg.Glyph),
codepoints: std.AutoHashMapUnmanaged(CodepointKey, u32) = .{},

pub fn init(alloc: Allocator, opts: facepkg.Options) !Grid {
    var atlas_grayscale = try Atlas.init(alloc, 512, .grayscale);
    errdefer atlas_grayscale.deinit(alloc);

    var collection = Collection.init();

    const regular = try Face.init(embedpkg.GeistMono, opts);

    var bold = try Face.init(embedpkg.GeistMono, opts);

    try bold.setVariations(
        &.{
            .{ .id = facepkg.Variation.Id.init("wght"), .value = 800 },
        },
        opts,
    );
    const italic = try Face.init(embedpkg.GeistMonoItalic, opts);

    var bold_italic = try Face.init(embedpkg.GeistMonoItalic, opts);

    try bold_italic.setVariations(
        &.{
            .{ .id = facepkg.Variation.Id.init("wght"), .value = 800 },
        },
        opts,
    );

    collection.add(regular, .regular);
    collection.add(bold, .bold);
    collection.add(italic, .italic);
    collection.add(bold_italic, .bold_italic);

    try collection.metric_modifiers.put(alloc, .cell_width, .{ .absolute = -1 });
    collection.reloadMetrics();

    var grid = Grid{
        .atlas_grayscale = atlas_grayscale,
        .resolver = .{
            .collection = collection,
        },
        .metrics = collection.metrics,
        .shaper = try Shaper.init(alloc),
        .glyphs = std.AutoHashMap(GlyphKey, fontpkg.Glyph).init(alloc),
    };
    errdefer grid.shaper.deinit();
    errdefer grid.glyphs.deinit();
    errdefer grid.codepoints.deinit(alloc);

    return grid;
}

fn reloadMetrics(self: *Grid) !void {
    self.resolver.collection.reloadMetrics();
    self.metrics = self.resolver.collection.metrics;
}

pub fn cellSize(self: *Grid) sizepkg.CellSize {
    return .{ .width = self.metrics.cell_width, .height = self.metrics.cell_height };
}

pub fn deinit(self: *Grid, alloc: Allocator) void {
    self.atlas_grayscale.deinit(alloc);
    self.resolver.deinit(alloc);
    self.shaper.deinit();
    self.glyphs.deinit();
    self.codepoints.deinit(alloc);
}

pub fn shapeRow(self: *Grid, alloc: Allocator, codepoints: []const u32) ![]const Shaper.ShapedGlyph {
    return self.shaper.shapeRow(alloc, self.resolver.collection.faces.getPtr(.regular), self.metrics, codepoints);
}

pub fn renderCodepoint(self: *Grid, alloc: Allocator, cp: u32, style: Style) !?fontpkg.Glyph {
    const index = try self.getIndex(alloc, cp, style) orelse return null;

    return try self.renderGlyph(alloc, index, style);
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

    const face = self.resolver.getFace(style);

    if (face.glyphIndex(cp)) |index| {
        try self.codepoints.put(alloc, .{ .codepoint = cp, .style = style }, index);
        return index;
    }

    return null;
}

pub fn renderGlyph(self: *Grid, alloc: Allocator, index: u32, style: Style) !fontpkg.Glyph {
    {
        self.lock.lockShared();
        defer self.lock.unlockShared();

        if (self.glyphs.get(.{ .index = index, .style = style })) |cached_glyph| {
            return cached_glyph;
        }
    }

    self.lock.lock();
    defer self.lock.unlock();

    const atlas = &self.atlas_grayscale;
    const raw_index = index;

    const face = self.resolver.getFace(style);
    const glyph = try face.renderGlyph(alloc, atlas, raw_index, .{
        .grid_metrics = self.metrics,
    });
    try self.glyphs.put(.{ .index = index, .style = style }, glyph);

    return glyph;
}
