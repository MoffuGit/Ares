const std = @import("std");
const Allocator = std.mem.Allocator;
const macos = @import("macos");
const fontpkg = @import("mod.zig");
const facepkg = @import("face/mod.zig");
const embedpkg = @import("embedded/mod.zig");

const foundation = macos.foundation;
const text = macos.text;

pub const ShapedGlyph = struct {
    column: usize,
    glyph_index: u32,
    x_offset: i16,
    y_offset: i16,
};

alloc: Allocator,
typesetter_attr_dict: *foundation.Dictionary,
cache: std.AutoHashMapUnmanaged(u64, []const ShapedGlyph) = .{},

const CodepointEntry = struct {
    codepoint: u32,
    cluster: u32,
};

const Offset = struct {
    cluster: u32 = 0,
    x: f64 = 0,
};

pub fn init(alloc: Allocator) !@This() {
    const embedding_level: c_int = 0;
    const num = try foundation.Number.create(.int, &embedding_level);
    defer num.release();

    const dict = try foundation.Dictionary.create(
        &.{macos.c.kCTTypesetterOptionForcedEmbeddingLevel},
        &.{num},
    );

    return .{
        .alloc = alloc,
        .typesetter_attr_dict = dict,
    };
}

pub fn deinit(self: *@This()) void {
    var it = self.cache.valueIterator();
    while (it.next()) |slice| {
        self.alloc.free(slice.*);
    }
    self.cache.deinit(self.alloc);
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
    _ = metrics;

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const scratch = arena.allocator();

    const row_hash = hashCodepoints(codepoints);
    if (self.cache.get(row_hash)) |cached| return cached;

    var unichars: std.ArrayListUnmanaged(u16) = .{};
    defer unichars.deinit(scratch);

    var entries: std.ArrayListUnmanaged(CodepointEntry) = .{};
    defer entries.deinit(scratch);

    try unichars.ensureTotalCapacity(scratch, codepoints.len * 2);
    try entries.ensureTotalCapacity(scratch, codepoints.len * 2);

    for (codepoints) |cp| {
        var surrogate_pair: [2]u16 = undefined;
        if (foundation.stringGetSurrogatePairForLongCharacter(cp, &surrogate_pair)) {
            unichars.appendSliceAssumeCapacity(&surrogate_pair);
            entries.appendAssumeCapacity(.{ .codepoint = cp, .cluster = 0 });
            entries.appendAssumeCapacity(.{ .codepoint = 0, .cluster = 0 });
            continue;
        }

        std.debug.assert(cp <= std.math.maxInt(u16));
        unichars.appendAssumeCapacity(@intCast(cp));
        entries.appendAssumeCapacity(.{ .codepoint = cp, .cluster = 0 });
    }

    const str = foundation.String.createWithCharactersNoCopy(unichars.items);
    defer str.release();

    assignClusters(str, entries.items);

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
    errdefer shaped.deinit(self.alloc);
    try shaped.ensureTotalCapacity(self.alloc, line.getGlyphCount());

    var run_offset: Offset = .{};
    var cell_offset: Offset = .{};
    var non_ltr = false;
    const runs = line.getGlyphRuns();
    for (0..runs.getCount()) |run_idx| {
        const ctrun = runs.getValueAtIndex(text.Run, run_idx);

        const status = ctrun.getStatus();
        if (status.non_monotonic or status.right_to_left) non_ltr = true;

        const glyphs = ctrun.getGlyphsPtr() orelse try ctrun.getGlyphs(scratch);
        const advances = ctrun.getAdvancesPtr() orelse try ctrun.getAdvances(scratch);
        const positions = ctrun.getPositionsPtr() orelse try ctrun.getPositions(scratch);
        const indices = ctrun.getStringIndicesPtr() orelse try ctrun.getStringIndices(scratch);

        std.debug.assert(glyphs.len == advances.len);
        std.debug.assert(glyphs.len == positions.len);
        std.debug.assert(glyphs.len == indices.len);

        for (glyphs, advances, positions, indices) |glyph, advance, position, index| {
            if (index >= entries.items.len) continue;

            const cluster = entries.items[index].cluster;
            if (cell_offset.cluster != cluster) {
                const is_after_glyph_from_current_or_next_clusters = cluster <= run_offset.cluster;
                const is_first_codepoint_in_cluster = blk: {
                    var i = index;
                    while (i > 0) {
                        i -= 1;
                        const entry = entries.items[i];
                        if (entry.codepoint == 0) continue;
                        break :blk entry.cluster != cluster;
                    }
                    break :blk true;
                };

                if (is_first_codepoint_in_cluster and !is_after_glyph_from_current_or_next_clusters) {
                    cell_offset = .{
                        .cluster = cluster,
                        .x = run_offset.x,
                    };
                }
            }

            const x_offset = clampI16(@intFromFloat(@round(position.x - cell_offset.x)));
            const y_offset = clampI16(@intFromFloat(@round(position.y)));

            shaped.appendAssumeCapacity(.{
                .column = cell_offset.cluster,
                .glyph_index = @intCast(glyph),
                .x_offset = x_offset,
                .y_offset = y_offset,
            });

            run_offset.x += advance.width;
            run_offset.cluster = @max(run_offset.cluster, cluster);
        }
    }

    if (non_ltr) {
        std.mem.sort(
            ShapedGlyph,
            shaped.items,
            {},
            struct {
                fn lessThan(_: void, a: ShapedGlyph, b: ShapedGlyph) bool {
                    return a.column < b.column;
                }
            }.lessThan,
        );
    }

    const owned = try shaped.toOwnedSlice(self.alloc);
    errdefer self.alloc.free(owned);

    if (self.cache.count() >= 256) self.clearCache();

    const gop = try self.cache.getOrPut(self.alloc, row_hash);
    if (gop.found_existing) {
        self.alloc.free(gop.value_ptr.*);
    }
    gop.value_ptr.* = owned;

    return owned;
}

fn clampI16(v: i32) i16 {
    return std.math.cast(i16, std.math.clamp(v, std.math.minInt(i16), std.math.maxInt(i16))) orelse unreachable;
}

fn assignClusters(str: *foundation.String, entries: []CodepointEntry) void {
    var utf16_index: usize = 0;
    var cluster: u32 = 0;
    while (utf16_index < entries.len) {
        const range: foundation.Range = @bitCast(macos.c.CFStringGetRangeOfComposedCharactersAtIndex(
            @ptrCast(str),
            @intCast(utf16_index),
        ));

        const start: usize = @intCast(range.location);
        const end = start + @as(usize, @intCast(range.length));
        for (start..end) |i| {
            entries[i].cluster = cluster;
        }

        utf16_index = end;
        cluster += 1;
    }
}

fn hashCodepoints(codepoints: []const u32) u64 {
    var hasher = std.hash.Wyhash.init(0);
    for (codepoints) |cp| {
        std.hash.autoHash(&hasher, cp);
    }
    std.hash.autoHash(&hasher, codepoints.len);
    return hasher.final();
}

fn clearCache(self: *@This()) void {
    var it = self.cache.valueIterator();
    while (it.next()) |slice| {
        self.alloc.free(slice.*);
    }
    self.cache.clearRetainingCapacity();
}

test "shapeRow keeps combining sequence in one cluster" {
    var shaper = try @This().init(std.testing.allocator);
    defer shaper.deinit();

    var face = try facepkg.Face.init(embedpkg.GeistMono, .{
        .size = .{ .points = 12 },
    });
    defer face.deinit();

    const metrics = facepkg.Metrics.calc(face.getMetrics());
    const shaped = try shaper.shapeRow(std.testing.allocator, &face, metrics, &.{ 'e', 0x0301 });

    try std.testing.expect(shaped.len > 0);
    for (shaped) |glyph| {
        try std.testing.expectEqual(@as(usize, 0), glyph.column);
    }
}

test "shapeRow caches identical rows" {
    var shaper = try @This().init(std.testing.allocator);
    defer shaper.deinit();

    var face = try facepkg.Face.init(embedpkg.GeistMono, .{
        .size = .{ .points = 12 },
    });
    defer face.deinit();

    const metrics = facepkg.Metrics.calc(face.getMetrics());
    const first = try shaper.shapeRow(std.testing.allocator, &face, metrics, &.{ 'a', 'b', 'c' });
    const second = try shaper.shapeRow(std.testing.allocator, &face, metrics, &.{ 'a', 'b', 'c' });

    try std.testing.expectEqual(@intFromPtr(first.ptr), @intFromPtr(second.ptr));
}
