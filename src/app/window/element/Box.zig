const std = @import("std");
const vaxis = @import("vaxis");
const Element = @import("mod.zig");
const Buffer = @import("../../Buffer.zig");
const TypedElement = @import("TypedElement.zig").TypedElement;
const Style = Element.Style;
const Allocator = std.mem.Allocator;

const Box = @This();

const TE = TypedElement(Box);

element: TE,

bg: vaxis.Color = .default,
fg: vaxis.Color = .default,
segments: ?[]const Element.Segment = null,
text_align: Element.TextAlign = .left,
rounded: ?f32 = null,
border: ?Border = null,

pub const Border = struct {
    top: []const u8 = "─",
    bottom: []const u8 = "─",
    left: []const u8 = "│",
    right: []const u8 = "│",
    top_left: []const u8 = "┌",
    top_right: []const u8 = "┐",
    bottom_left: []const u8 = "└",
    bottom_right: []const u8 = "┘",
    fg: vaxis.Color = .default,
    bg: vaxis.Color = .default,

    pub const single = Border{};

    pub const rounded = Border{
        .top_left = "╭",
        .top_right = "╮",
        .bottom_left = "╰",
        .bottom_right = "╯",
    };

    pub const double = Border{
        .top = "═",
        .bottom = "═",
        .left = "║",
        .right = "║",
        .top_left = "╔",
        .top_right = "╗",
        .bottom_left = "╚",
        .bottom_right = "╝",
    };

    pub const heavy = Border{
        .top = "━",
        .bottom = "━",
        .left = "┃",
        .right = "┃",
        .top_left = "┏",
        .top_right = "┓",
        .bottom_left = "┗",
        .bottom_right = "┛",
    };

    pub const block = Border{
        .top = "▄",
        .bottom = "▀",
        .left = "▐",
        .right = "▌",
        .top_left = "▗",
        .top_right = "▖",
        .bottom_left = "▝",
        .bottom_right = "▘",
    };
};

pub const Options = struct {
    id: ?[]const u8 = null,
    visible: bool = true,
    zIndex: usize = 0,
    style: Style = .{},
    bg: vaxis.Color = .default,
    fg: vaxis.Color = .default,
    segments: ?[]const Element.Segment = null,
    text_align: Element.TextAlign = .left,
    rounded: ?f32 = null,
    border: ?Border = null,
};

pub fn init(alloc: Allocator, opts: Options) !*Box {
    const self = try alloc.create(Box);
    errdefer alloc.destroy(self);

    var style = opts.style;

    if (opts.border != null) {
        if (style.border.all == null and
            style.border.left == null and
            style.border.right == null and
            style.border.top == null and
            style.border.bottom == null and
            style.border.horizontal == null and
            style.border.vertical == null)
        {
            style.border = Style.BorderEdges.uniform(1);
        }
    }

    self.* = .{
        .element = TE.init(alloc, self, .{
            .drawFn = draw,
        }, .{
            .id = opts.id,
            .visible = opts.visible,
            .zIndex = opts.zIndex,
            .style = style,
        }),
        .bg = opts.bg,
        .fg = opts.fg,
        .segments = opts.segments,
        .text_align = opts.text_align,
        .rounded = opts.rounded,
        .border = opts.border,
    };

    return self;
}

pub fn deinit(self: *Box, alloc: Allocator) void {
    self.element.deinit();
    alloc.destroy(self);
}

pub fn elem(self: *Box) *Element {
    return self.element.elem();
}

fn draw(self: *Box, element: *Element, buffer: *Buffer) void {
    const layout = element.layout;

    if (self.rounded) |radius| {
        element.fillRounded(buffer, self.bg, radius);
    } else {
        element.fill(buffer, .{ .style = .{ .bg = self.bg, .fg = self.fg } });
    }

    if (self.border) |border| {
        const bl = layout.border.left;
        const bt = layout.border.top;
        const br = layout.border.right;
        const bb = layout.border.bottom;

        const l = layout.left;
        const t = layout.top;
        const w = layout.width;
        const h = layout.height;

        const border_style: vaxis.Style = .{ .fg = border.fg, .bg = border.bg };

        // top edge
        if (bt > 0) {
            var col: u16 = bl;
            while (col < w -| br) : (col += 1) {
                buffer.writeCell(l + col, t, .{ .char = .{ .grapheme = border.top }, .style = border_style });
            }
        }

        // bottom edge
        if (bb > 0 and h > bt) {
            var col: u16 = bl;
            while (col < w -| br) : (col += 1) {
                buffer.writeCell(l + col, t + h -| 1, .{ .char = .{ .grapheme = border.bottom }, .style = border_style });
            }
        }

        // left edge
        if (bl > 0) {
            var row: u16 = bt;
            while (row < h -| bb) : (row += 1) {
                buffer.writeCell(l, t + row, .{ .char = .{ .grapheme = border.left }, .style = border_style });
            }
        }

        // right edge
        if (br > 0 and w > bl) {
            var row: u16 = bt;
            while (row < h -| bb) : (row += 1) {
                buffer.writeCell(l + w -| 1, t + row, .{ .char = .{ .grapheme = border.right }, .style = border_style });
            }
        }

        // corners
        if (bt > 0 and bl > 0) {
            buffer.writeCell(l, t, .{ .char = .{ .grapheme = border.top_left }, .style = border_style });
        }
        if (bt > 0 and br > 0 and w > 1) {
            buffer.writeCell(l + w -| 1, t, .{ .char = .{ .grapheme = border.top_right }, .style = border_style });
        }
        if (bb > 0 and bl > 0 and h > 1) {
            buffer.writeCell(l, t + h -| 1, .{ .char = .{ .grapheme = border.bottom_left }, .style = border_style });
        }
        if (bb > 0 and br > 0 and w > 1 and h > 1) {
            buffer.writeCell(l + w -| 1, t + h -| 1, .{ .char = .{ .grapheme = border.bottom_right }, .style = border_style });
        }
    }

    if (self.segments) |segments| {
        _ = element.print(buffer, segments, .{
            .row_offset = layout.border.top + layout.padding.top,
            .col_offset = layout.border.left + layout.padding.left,
            .text_align = self.text_align,
        });
    }
}
