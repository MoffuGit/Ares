const std = @import("std");
const vaxis = @import("vaxis");
const unicode = vaxis.unicode;
const gwidth = vaxis.gwidth.gwidth;
const lib = @import("../lib.zig");
const global = @import("../global.zig");

const Element = lib.Element;
const Buffer = lib.Buffer;
const Context = lib.App.Context;
const Dialog = @import("styled/Dialog.zig");
const Input = @import("../app/window/element/Input.zig");
const CommandList = @import("CommandList.zig");
const Allocator = std.mem.Allocator;

const Command = @This();

alloc: Allocator,
ctx: *Context,
dialog: *Dialog,
input: *Input,
list: *CommandList,
prev_focused: ?*Element.Element = null,

pub fn create(alloc: Allocator, ctx: *Context) !*Command {
    const self = try alloc.create(Command);
    errdefer alloc.destroy(self);

    const theme = global.settings.theme;

    const dialog = try Dialog.create(
        alloc,
        ctx,
        .{
            .box = .{
                .style = .{
                    .width = .{ .point = 75 },
                    .height = .{ .point = 25 },
                    .position = .{
                        .top = .{ .point = -18 },
                    },
                    .align_items = .center,
                    .padding = .{ .horizontal = .{ .point = 1 } },
                },
                .border = .{
                    .kind = .thin_block,
                    .color = .{ .axes = .{ .vertical = .{
                        .bg = theme.mutedBg.setAlpha(0),
                        .fg = theme.border,
                    }, .horizontal = .{
                        .bg = theme.bg,
                        .fg = theme.border,
                    } } },
                },
                .bg = theme.bg,
                .fg = theme.fg,
            },
        },
    );
    errdefer dialog.destroy();

    const input = try Input.create(alloc, .{ .drawFn = drawInput }, .{
        .element = .{
            .id = "command-input",
            .style = .{
                .width = .{ .percent = 100 },
                .height = .{ .point = 1 },
            },
        },
    });
    errdefer input.destroy();

    const list = try CommandList.create(alloc);
    errdefer list.destroy();

    try dialog.box.element.childs(.{ input, list.container });

    self.* = .{
        .alloc = alloc,
        .ctx = ctx,
        .dialog = dialog,
        .input = input,
        .list = list,
    };

    return self;
}

pub fn toggleShow(self: *Command) void {
    const theme = global.settings.theme;
    const is_visible = self.dialog.portal.element.elem().visible;

    self.dialog.box.bg = theme.bg;
    self.dialog.box.fg = theme.fg;

    self.dialog.box.border =
        .{
            .kind = .thin_block,
            .color = .{ .axes = .{ .vertical = .{
                .bg = theme.mutedBg.setAlpha(0),
                .fg = theme.border,
            }, .horizontal = .{
                .bg = theme.bg,
                .fg = theme.border,
            } } },
        };

    if (!is_visible) {
        self.prev_focused = self.ctx.app.window.getFocus();
        self.ctx.app.window.setFocus(self.input.elem());
    } else {
        self.ctx.app.window.setFocus(self.prev_focused);
        self.prev_focused = null;
    }

    self.dialog.toggleShow();
}

fn drawInput(input: *Input, element: *Element, buffer: *Buffer) void {
    const layout = element.layout;
    const theme = global.settings.theme;

    element.fill(buffer, .{ .style = .{ .bg = theme.bg } });

    const base_x = layout.left;
    const base_y = layout.top;
    const width = layout.width;

    var col: u16 = 0;

    const before = input.buf.items;
    var iter_before = unicode.graphemeIterator(before);
    while (iter_before.next()) |grapheme| {
        const s = grapheme.bytes(before);
        const w: u16 = @intCast(gwidth(s, .unicode));
        if (col + w > width) break;
        buffer.writeCell(base_x + col, base_y, .{
            .char = .{ .grapheme = s, .width = @intCast(w) },
            .style = .{ .fg = theme.fg, .bg = theme.bg },
        });
        col += w;
    }

    const cursor_col = col;
    const second = input.buf.secondHalf();
    const cursor_char = blk: {
        var it = unicode.graphemeIterator(second);
        if (it.next()) |g| break :blk g.bytes(second);
        break :blk " ";
    };
    const cursor_w: u16 = @intCast(@max(1, gwidth(cursor_char, .unicode)));
    if (cursor_col + cursor_w <= width) {
        buffer.writeCell(base_x + cursor_col, base_y, .{
            .char = .{ .grapheme = cursor_char, .width = @intCast(cursor_w) },
            .style = .{ .fg = theme.bg, .bg = theme.fg },
        });
    }

    col = cursor_col + cursor_w;
    var iter_after = unicode.graphemeIterator(second);
    _ = iter_after.next();
    while (iter_after.next()) |grapheme| {
        const s = grapheme.bytes(second);
        const w: u16 = @intCast(gwidth(s, .unicode));
        if (col + w > width) break;
        buffer.writeCell(base_x + col, base_y, .{
            .char = .{ .grapheme = s, .width = @intCast(w) },
            .style = .{ .fg = theme.fg, .bg = theme.bg },
        });
        col += w;
    }
}

pub fn destroy(self: *Command) void {
    self.input.destroy();
    self.dialog.destroy();
    self.alloc.destroy(self);
}
