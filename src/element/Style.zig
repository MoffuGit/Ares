const vaxis = @import("vaxis");

pub const Style = @This();

pub const Underline = enum {
    off,
    single,
    double,
    curly,
    dotted,
    dashed,
};

fg: vaxis.Color = .default,
bg: vaxis.Color = .default,
ul: vaxis.Color = .default,
ul_style: Underline = .off,

bold: bool = false,
dim: bool = false,
italic: bool = false,
blink: bool = false,
reverse: bool = false,
invisible: bool = false,
strikethrough: bool = false,

pub fn cellStyle(self: Style) vaxis.Style {
    return .{
        .fg = self.fg,
        .bg = self.bg,
        .ul = self.ul,
        .ul_style = @enumFromInt(@intFromEnum(self.ul_style)),
        .bold = self.bold,
        .dim = self.dim,
        .italic = self.italic,
        .blink = self.blink,
        .reverse = self.reverse,
        .invisible = self.invisible,
        .strikethrough = self.strikethrough,
    };
}
