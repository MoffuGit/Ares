const std = @import("std");
const Allocator = std.mem.Allocator;
const macos = @import("macos");
const fontpkg = @import("mod.zig");
const facepkg = @import("face/mod.zig");

const foundation = macos.foundation;
const text = macos.text;

pub const ShapedGlyph = struct {
    column: usize,
    glyph_index: u32,
    x_offset: i16,
    y_offset: i16,
};

typesetter_attr_dict: *foundation.Dictionary,

pub fn init() !@This() {
    const embedding_level: c_int = 0;
    const num = try foundation.Number.create(.int, &embedding_level);
    defer num.release();

    const dict = try foundation.Dictionary.create(
        &.{macos.c.kCTTypesetterOptionForcedEmbeddingLevel},
        &.{num},
    );

    return .{ .typesetter_attr_dict = dict };
}

pub fn deinit(self: *@This()) void {
    self.typesetter_attr_dict.release();
}

pub fn shapeRow(
    self: *@This(),
    alloc: Allocator,
    face: *facepkg.Face,
    metrics: fontpkg.Metrics,
    codepoints: []const u32,
) ![]const ShapedGlyph {
    if (codepoints.len == 0) return &.{};

    var unichars: std.ArrayListUnmanaged(u16) = .{};
    defer unichars.deinit(alloc);

    var clusters: std.ArrayListUnmanaged(usize) = .{};
    defer clusters.deinit(alloc);

    try unichars.ensureTotalCapacity(alloc, codepoints.len * 2);
    try clusters.ensureTotalCapacity(alloc, codepoints.len * 2);

    for (codepoints, 0..) |cp, column| {
        var surrogate_pair: [2]u16 = undefined;
        if (foundation.stringGetSurrogatePairForLongCharacter(cp, &surrogate_pair)) {
            unichars.appendSliceAssumeCapacity(&surrogate_pair);
            clusters.appendAssumeCapacity(column);
            clusters.appendAssumeCapacity(column);
            continue;
        }

        std.debug.assert(cp <= std.math.maxInt(u16));
        unichars.appendAssumeCapacity(@intCast(cp));
        clusters.appendAssumeCapacity(column);
    }

    const str = foundation.String.createWithCharactersNoCopy(unichars.items);
    defer str.release();

    const attr = try foundation.MutableAttributedString.create(unichars.items.len);
    defer attr.release();
    attr.replaceString(foundation.Range.init(0, 0), str);
    attr.setAttribute(
        foundation.Range.init(0, str.getLength()),
        text.StringAttribute.font,
        face.font,
    );

    const attr_str: *foundation.AttributedString = @ptrCast(attr);
    const typesetter = try text.Typesetter.createWithAttributedStringAndOptions(
        attr_str,
        self.typesetter_attr_dict,
    );
    defer typesetter.release();

    const line = typesetter.createLine(.{ .location = 0, .length = 0 });
    defer line.release();

    var shaped: std.ArrayListUnmanaged(ShapedGlyph) = .{};
    errdefer shaped.deinit(alloc);
    try shaped.ensureTotalCapacity(alloc, line.getGlyphCount());

    const cell_width: f64 = @floatFromInt(metrics.cell_width);
    const runs = line.getGlyphRuns();
    for (0..runs.getCount()) |run_idx| {
        const ctrun = runs.getValueAtIndex(text.Run, run_idx);

        const glyphs = ctrun.getGlyphsPtr() orelse try ctrun.getGlyphs(alloc);
        const positions = ctrun.getPositionsPtr() orelse try ctrun.getPositions(alloc);
        const indices = ctrun.getStringIndicesPtr() orelse try ctrun.getStringIndices(alloc);

        std.debug.assert(glyphs.len == positions.len);
        std.debug.assert(glyphs.len == indices.len);

        for (glyphs, positions, indices) |glyph, position, index| {
            if (index >= clusters.items.len) continue;

            const column = clusters.items[index];
            const cluster_x = @as(f64, @floatFromInt(column)) * cell_width;
            const x_offset = clampI16(@intFromFloat(@round(position.x - cluster_x)));
            const y_offset = clampI16(@intFromFloat(@round(position.y)));

            shaped.appendAssumeCapacity(.{
                .column = column,
                .glyph_index = @intCast(glyph),
                .x_offset = x_offset,
                .y_offset = y_offset,
            });
        }
    }

    return shaped.toOwnedSlice(alloc);
}

fn clampI16(v: i32) i16 {
    return std.math.cast(i16, std.math.clamp(v, std.math.minInt(i16), std.math.maxInt(i16))) orelse unreachable;
}
