const std = @import("std");
const tui = @import("tui");
const global = @import("../global.zig");

const Element = tui.Element;
const Buffer = tui.Buffer;
const Workspace = @import("../workspace/mod.zig");
const Context = tui.App.Context;

const TopBar = @This();

const TE = Element.TypedElement(TopBar);
const ColorAnim = TE.Anim(tui.Color);

element: TE,
workspace: *Workspace,
entry_color: ?tui.Color = null,
entry_id: ?u64 = null,
color_anim: ColorAnim,

fn lerpColor(a: tui.Color, b: tui.Color, t: f32) tui.Color {
    const a_rgba = a.rgba;
    const b_rgba = b.rgba;
    var new: [4]u8 = undefined;
    inline for (0..3) |i| {
        const a_f: f32 = @as(f32, @floatFromInt(a_rgba[i])) / 255.0;
        const b_f: f32 = @as(f32, @floatFromInt(b_rgba[i])) / 255.0;
        new[i] = @intFromFloat((a_f + (b_f - a_f) * t) * 255.0);
    }
    new[3] = a_rgba[3];

    return .{ .rgba = new };
}

fn colorCallback(self: *TopBar, state: tui.Color, ctx: *Context) void {
    self.entry_color = state;
    ctx.requestDraw();
}

pub fn create(alloc: std.mem.Allocator, workspace: *Workspace) !*TopBar {
    const self = try alloc.create(TopBar);
    errdefer alloc.destroy(self);

    self.* = .{
        .workspace = workspace,
        .element = TE.init(alloc, self, .{
            .drawFn = draw,
        }, .{
            .id = "top-bar",
            .style = .{
                .width = .stretch,
                .height = .{ .point = 2 },
                .margin = .{ .horizontal = .{ .point = 1 } },
                .flex_shrink = 0,
            },
        }),
        .color_anim = ColorAnim.init(self, colorCallback, .{
            .start = .default,
            .end = .default,
            .duration_us = 100_000,
            .updateFn = lerpColor,
            .easing = .linear,
        }),
    };

    return self;
}

pub fn destroy(self: *TopBar, alloc: std.mem.Allocator) void {
    self.element.deinit();
    alloc.destroy(self);
}

fn draw(_: *TopBar, element: *Element, buffer: *Buffer) void {
    const theme = global.engine.settings.theme;

    element.fill(buffer, .{ .style = .{
        .bg = .{ .rgba = theme.bg.rgba },
    } });

    buffer.fillRect(element.layout.left -| 1, element.layout.top + 1, element.layout.width + 2, 1, .{ .char = .{
        .grapheme = "▄",
    }, .style = .{ .fg = .{ .rgba = theme.mutedBg.rgba }, .bg = .{ .rgba = theme.bg.rgba } } });
}
