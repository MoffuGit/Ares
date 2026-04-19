pub const facepkg = @import("face/mod.zig");
pub const Metrics = @import("Metrics.zig");
pub const Grid = @import("Grid.zig");
pub const Atlas = @import("Atlas.zig");
pub const Glyph = @import("Glyph.zig");
pub const Shaper = @import("Shaper.zig");

pub const Style = enum(u3) {
    regular = 0,
    bold = 1,
    italic = 2,
    bold_italic = 3,
};
