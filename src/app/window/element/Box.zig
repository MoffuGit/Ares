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
shadow: ?Shadow = null,
opacity: f32 = 1.0,

pub const Shadow = struct {
    color: vaxis.Color = .{ .rgba = .{ 0, 0, 0, 64 } },
    offset_x: i16 = 1,
    offset_y: i16 = 1,
    spread: u16 = 0,
    opacity: f32 = 0.1,
};

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
    shadow: ?Shadow = null,
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
        .shadow = opts.shadow,
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
    const opacity = self.opacity;

    if (self.shadow) |shadow| {
        const initial_alpha = shadow.color.alpha() * opacity;
        if (initial_alpha > 0.0) {
            const sx: i32 = @as(i32, layout.left) + shadow.offset_x - @as(i32, shadow.spread);
            const sy: i32 = @as(i32, layout.top) + shadow.offset_y - @as(i32, shadow.spread);
            const sw: u16 = layout.width +| shadow.spread *| 2;
            const sh: u16 = layout.height +| shadow.spread *| 2;

            const inner_left: i32 = @as(i32, layout.left) + shadow.offset_x;
            const inner_top: i32 = @as(i32, layout.top) + shadow.offset_y;
            const inner_right: i32 = inner_left + @as(i32, layout.width);
            const inner_bottom: i32 = inner_top + @as(i32, layout.height);

            var py: u16 = 0;
            while (py < sh) : (py += 1) {
                const row: i32 = sy + py;
                if (row < 0 or row >= buffer.height) continue;
                var px: u16 = 0;
                while (px < sw) : (px += 1) {
                    const col: i32 = sx + px;
                    if (col < 0 or col >= buffer.width) continue;

                    const dx: u16 = if (col < inner_left)
                        @intCast(inner_left - col)
                    else if (col >= inner_right)
                        @intCast(col - inner_right + 1)
                    else
                        0;

                    const dy: u16 = if (row < inner_top)
                        @intCast(inner_top - row)
                    else if (row >= inner_bottom)
                        @intCast(row - inner_bottom + 1)
                    else
                        0;

                    const dist = @max(dx, dy);
                    const alpha = initial_alpha - @as(f32, @floatFromInt(dist)) * shadow.opacity;
                    if (alpha <= 0.0) continue;

                    buffer.writeCell(@intCast(col), @intCast(row), .{
                        .style = .{ .bg = shadow.color.setAlpha(alpha) },
                    });
                }
            }
        }
    }

    const bg = self.bg.setAlpha(self.bg.alpha() * opacity);
    const fg = self.fg.setAlpha(self.fg.alpha() * opacity);

    if (self.rounded) |radius| {
        element.fillRounded(buffer, bg, radius);
    } else {
        element.fill(buffer, .{ .style = .{ .bg = bg, .fg = fg } });
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

        const border_style: vaxis.Style = .{
            .fg = border.fg.setAlpha(border.fg.alpha() * opacity),
            .bg = border.bg.setAlpha(border.bg.alpha() * opacity),
        };

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
