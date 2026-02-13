const std = @import("std");
const vaxis = @import("vaxis");
const lib = @import("../../lib.zig");
const global = @import("../../global.zig");

const Element = lib.Element;
const Buffer = lib.Buffer;
const Workspace = lib.Workspace;
const Context = lib.App.Context;
const Portal = @import("Portal.zig");
const Box = Element.Box;
const Allocator = std.mem.Allocator;

const Dialog = @This();

alloc: Allocator,
box: *Box,
portal: *Portal,

const Options = struct {
    portal: Portal.Options = .{},
    style: Element.Style = .{},
};

pub fn create(alloc: Allocator, ctx: *Context, opts: Options) !*Dialog {
    const portal = try Portal.create(alloc, opts.portal);
    errdefer portal.destroy();

    const box = try Box.init(alloc, .{
        .style = .{
            .width = .{ .percent = 33 },
            .height = .{ .percent = 33 },
            .align_self = .center,
        },
    });
    errdefer box.deinit(alloc);

    portal.element.childs(.{box.element});

    const dialog = try alloc.create(Dialog);
    errdefer alloc.destroy(dialog);

    const root = ctx.app.root();

    const element = portal.element.elem();
    try root.addChild(element);
    errdefer root.removeChild(element);

    dialog.* = .{
        .box = box,
        .portal = portal,
    };

    portal.element.elem().hide();

    return dialog;
}

pub fn destroy(self: *Dialog) void {
    self.portal.destroy();
    self.box.deinit(self.alloc);
}
