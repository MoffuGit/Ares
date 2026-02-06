const std = @import("std");
const lib = @import("../lib.zig");
const global = @import("../global.zig");

const Element = lib.Element;
const Buffer = lib.Buffer;
const Workspace = lib.Workspace;
const Settings = @import("../settings/mod.zig");

const BottomBar = @This();

element: *Element,
settings: *Settings,
workspace: *Workspace,

pub fn create(alloc: std.mem.Allocator, workspace: *Workspace) !*BottomBar {
    const self = try alloc.create(BottomBar);
    errdefer alloc.destroy(self);

    const element = try alloc.create(Element);
    errdefer alloc.destroy(element);

    element.* = Element.init(alloc, .{
        .id = "bottom-bar",
        .drawFn = draw,
        .userdata = self,
        .style = .{
            .width = .{ .percent = 100 },
            .height = .{ .point = 1 },
            .flex_shrink = 0,
        },
    });

    self.* = .{
        .workspace = workspace,
        .element = element,
        .settings = global.settings,
    };

    return self;
}

pub fn destroy(self: *BottomBar, alloc: std.mem.Allocator) void {
    self.element.deinit();
    alloc.destroy(self.element);
    alloc.destroy(self);
}

pub fn getElement(self: *BottomBar) *Element {
    return self.element;
}

fn draw(element: *Element, buffer: *Buffer) void {
    const self: *BottomBar = @ptrCast(@alignCast(element.userdata));
    element.fill(buffer, .{ .style = .{ .bg = self.settings.theme.bg } });
}
