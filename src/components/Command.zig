const std = @import("std");
const lib = @import("../lib.zig");
const global = @import("../global.zig");

const Element = lib.Element;
const Buffer = lib.Buffer;
const Context = lib.App.Context;
const Dialog = @import("styled/Dialog.zig");
const Allocator = std.mem.Allocator;

const Command = @This();

alloc: Allocator,
dialog: *Dialog,

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
                },
                .border = .{
                    .kind = .thin_block,
                    .color = .{ .axes = .{ .horizontal = .{
                        .bg = theme.mutedBg.setAlpha(0),
                        .fg = theme.border,
                    }, .vertical = .{
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

    self.* = .{
        .alloc = alloc,
        .dialog = dialog,
    };

    return self;
}

pub fn toggleShow(self: *Command) void {
    const theme = global.settings.theme;

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
    self.dialog.toggleShow();
}

pub fn destroy(self: *Command) void {
    self.dialog.destroy();
    self.alloc.destroy(self);
}
