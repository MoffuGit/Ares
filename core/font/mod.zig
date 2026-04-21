pub const facepkg = @import("face/mod.zig");
pub const Metrics = @import("Metrics.zig");
pub const Grid = @import("Grid.zig");
pub const Atlas = @import("Atlas.zig");
pub const Glyph = @import("Glyph.zig");
pub const Shaper = @import("Shaper.zig");
const zintect = @import("zintect");

pub const Style = enum(u3) {
    regular = 0,
    bold = 1,
    italic = 2,
    bold_italic = 3,

    pub fn fromSpan(span: zintect.FffSpan) Style {
        const style = span.fontStyle();
        if (style.bold and style.italic) return .bold_italic;
        if (style.bold) return .bold;
        if (style.italic) return .italic;
        return .regular;
    }
};
