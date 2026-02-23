const std = @import("std");
const tui = @import("tui");
const global = @import("../global.zig");

const TypedElement = tui.TypedElement;
const Element = tui.Element;
const Buffer = tui.Buffer;
const Workspace = @import("../workspace/mod.zig");

const BottomBar = @This();
const BottomBarElement = TypedElement(BottomBar);

element: BottomBarElement,
workspace: *Workspace,

pub fn create(alloc: std.mem.Allocator, workspace: *Workspace) !*BottomBar {
    const self = try alloc.create(BottomBar);
    errdefer alloc.destroy(self);

    const element = BottomBarElement.init(
        alloc,
        self,
        .{ .drawFn = draw },
        .{
            .id = "bottom-bar",
            .style = .{
                .width = .{ .percent = 100 },
                .height = .{ .point = 1 },
                .flex_shrink = 0,
            },
        },
    );

    self.* = .{
        .workspace = workspace,
        .element = element,
    };

    return self;
}

pub fn destroy(self: *BottomBar, alloc: std.mem.Allocator) void {
    self.element.deinit();
    alloc.destroy(self);
}

fn draw(_: *BottomBar, element: *Element, buffer: *Buffer) void {
    const theme = global.engine.settings.theme;

    element.fill(buffer, .{ .style = .{
        .bg = .{ .rgba = theme.bg.rgba },
        .fg = .{ .rgba = theme.mutedFg.rgba },
    }, .char = .{ .grapheme = "/" } });

    const mode_text, const mode_color: [4]u8 = switch (global.engine.mode) {
        .normal => .{ " NORMAL ", .{ 100, 149, 237, 255 } },
        .insert => .{ " INSERT ", .{ 80, 200, 120, 255 } },
        .visual => .{ " VISUAL ", .{ 180, 120, 220, 255 } },
    };

    _ = mode_color;
    _ = element.print(buffer, &.{
        .{
            .text = mode_text,
            .style = .{
                .bg = .{ .rgba = theme.bg.rgba },
                .fg = .{ .rgba = theme.mutedFg.rgba },
            },
        },
    }, .{
        .col_offset = 2,
    });
}
