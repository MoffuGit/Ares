const opentype = @import("../opentype/mod.zig");
const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const macos = @import("macos");

pub const ColorState = @This();
/// True if there is an sbix font table. For now, the mere presence
/// of an sbix font table causes us to assume the glyph is colored.
/// We can improve this later.
sbix: bool,

/// The SVG font table data (if any), which we can use to determine
/// if a glyph is present in the SVG table.
svg: ?opentype.SVG,
svg_data: ?*macos.foundation.Data,

pub const Error = error{InvalidSVGTable};

pub fn init(f: *macos.text.Font) Error!ColorState {
    // sbix is true if the table exists in the font data at all.
    // In the future we probably want to actually parse it and
    // check for glyphs.
    const sbix: bool = sbix: {
        const tag = macos.text.FontTableTag.init("sbix");
        const data = f.copyTable(tag) orelse break :sbix false;
        data.release();
        break :sbix data.getLength() > 0;
    };

    // Read the SVG table out of the font data.
    const svg: ?struct {
        svg: opentype.SVG,
        data: *macos.foundation.Data,
    } = svg: {
        const tag = macos.text.FontTableTag.init("SVG ");
        const data = f.copyTable(tag) orelse break :svg null;
        errdefer data.release();
        const ptr = data.getPointer();
        const len = data.getLength();
        const svg = opentype.SVG.init(ptr[0..len]) catch |err| {
            return switch (err) {
                error.EndOfStream,
                error.SVGVersionNotSupported,
                => error.InvalidSVGTable,
            };
        };

        break :svg .{
            .svg = svg,
            .data = data,
        };
    };

    return .{
        .sbix = sbix,
        .svg = if (svg) |v| v.svg else null,
        .svg_data = if (svg) |v| v.data else null,
    };
}

pub fn deinit(self: *const ColorState) void {
    if (self.svg_data) |v| v.release();
}

/// Returns true if the given glyph ID is colored.
pub fn isColorGlyph(self: *const ColorState, glyph_id: u32) bool {
    // Our font system uses 32-bit glyph IDs for special values but
    // actual fonts only contain 16-bit glyph IDs so if we can't cast
    // into it it must be false.
    const glyph_u16 = std.math.cast(u16, glyph_id) orelse return false;

    // sbix is always true for now
    if (self.sbix) return true;

    // if we have svg data, check it
    if (self.svg) |svg| {
        if (svg.hasGlyph(glyph_u16)) return true;
    }

    return false;
}
