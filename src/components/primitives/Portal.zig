const std = @import("std");
const vaxis = @import("vaxis");
const lib = @import("../../lib.zig");
const global = @import("../../global.zig");

const Element = lib.Element;
const Buffer = lib.Buffer;
const Workspace = lib.Workspace;
const HitGrid = lib.HitGrid;
const Context = lib.App.Context;
const Allocator = std.mem.Allocator;

const Portal = @This();
const PortalElement = Element.TypedElement(Portal);

const Backdrop = struct {
    enabled: bool = false,
    bg: vaxis.Color = .default,
    fg: vaxis.Color = .default,
};

alloc: Allocator,
element: PortalElement,
backdrop: Backdrop,
opacity: f32 = 1.0,

pub const Options = struct {
    backdrop: Backdrop = .{},
    zIndex: usize = 0,
    parent: *Element = undefined,
};

pub fn create(alloc: Allocator, opts: Options) !*Portal {
    const portal = try alloc.create(Portal);
    errdefer alloc.destroy(portal);

    portal.* = .{
        .alloc = alloc,
        .element = PortalElement.init(alloc, portal, .{
            .drawFn = draw,
            .hitFn = hit,
        }, .{
            .style = .{
                .width = .{ .percent = 100 },
                .height = .{ .percent = 100 },
                .position_type = .absolute,
                .align_self = .center,
            },
            .zIndex = 10,
        }),
        .backdrop = opts.backdrop,
    };

    const elem = portal.element.elem();
    try opts.parent.addChild(elem);
    errdefer opts.parent.removeChild(elem.num);

    return portal;
}

pub fn toggleShow(self: *Portal) void {
    const elem = self.element.elem();
    if (elem.visible) {
        elem.hide();
    } else {
        elem.show();
    }
}

pub fn destroy(self: *Portal) void {
    self.element.deinit();
    self.alloc.destroy(self);
}

pub fn draw(portal: *Portal, element: *Element, buffer: *Buffer) void {
    if (portal.backdrop.enabled) {
        element.fill(
            buffer,
            .{
                .style = .{
                    .bg = portal.backdrop.bg.setAlpha(portal.backdrop.bg.alpha() * portal.opacity),
                    .fg = portal.backdrop.fg.setAlpha(portal.backdrop.fg.alpha() * portal.opacity),
                },
            },
        );
    }
}

pub fn hit(portal: *Portal, element: *Element, hit_grid: *HitGrid) void {
    if (portal.backdrop.enabled) {
        element.hitSelf(hit_grid);
    }
}
