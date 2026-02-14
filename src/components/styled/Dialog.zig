const std = @import("std");
const vaxis = @import("vaxis");
const lib = @import("../../lib.zig");
const global = @import("../../global.zig");

const Element = lib.Element;
const Buffer = lib.Buffer;
const Workspace = lib.Workspace;
const Context = lib.App.Context;
const Portal = @import("../primitives/Portal.zig");
const Box = Element.Box;
const Allocator = std.mem.Allocator;

const Dialog = @This();

alloc: Allocator,
box: *Box,
portal: *Portal,

const Options = struct {
    portal: Portal.Options = .{},
    box: Box.Options = .{},
    style: Element.Style = .{},
};

pub fn create(alloc: Allocator, ctx: *Context, opts: Options) !*Dialog {
    var portal_opts = opts.portal;
    portal_opts.parent = ctx.app.root();

    const portal = try Portal.create(alloc, portal_opts);
    errdefer portal.destroy();

    const box = try Box.init(alloc, opts.box);
    errdefer box.deinit(alloc);

    try portal.element.childs(.{&box.element});

    const dialog = try alloc.create(Dialog);
    errdefer alloc.destroy(dialog);

    dialog.* = .{
        .alloc = alloc,
        .box = box,
        .portal = portal,
    };

    dialog.toggleShow();

    return dialog;
}

pub fn toggleShow(self: *Dialog) void {
    self.portal.toggleShow();
}

pub fn destroy(self: *Dialog) void {
    self.portal.destroy();
    self.box.deinit(self.alloc);
    self.alloc.destroy(self);
}
