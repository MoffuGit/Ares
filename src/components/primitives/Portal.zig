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

pub const Options = struct {
    backdrop: Backdrop = .{},
    zIndex: usize = 0,
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

    return portal;
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
                .style = .{ .bg = portal.backdrop.bg, .fg = portal.backdrop.fg },
            },
        );
    }
}

pub fn hit(portal: *Portal, element: *Element, hit_grid: *HitGrid) void {
    if (portal.backdrop.enabled) {
        element.hitSelf(hit_grid);
    }
}
