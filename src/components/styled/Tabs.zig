const std = @import("std");
const lib = @import("../../lib.zig");
const global = @import("../../global.zig");

const PrimitiveTabs = @import("../primitives/Tabs.zig");
const Element = lib.Element;
const Buffer = lib.Buffer;
const Allocator = std.mem.Allocator;
const Settings = @import("../../settings/mod.zig");

const Tabs = @This();

inner: PrimitiveTabs,

pub fn init(alloc: Allocator) !Tabs {
    return .{
        .inner = try PrimitiveTabs.init(alloc, .{
            .container = .{
                .id = "tabs-container",
                .style = .{
                    .width = .{ .percent = 100 },
                    .height = .{ .percent = 100 },
                },
            },
            .list = .{
                .id = "tabs-list",
                .drawFn = drawList,
                .style = .{
                    .width = .{ .percent = 100 },
                    .height = .{ .point = 1 },
                    .flex_direction = .row,
                    .flex_shrink = 0,
                },
            },
        }),
    };
}

pub fn deinit(self: *Tabs) void {
    self.inner.deinit();
}

pub fn newTab(self: *Tabs, opts: struct {
    content: Element.Options,
    userdata: ?*anyopaque = null,
}) !*PrimitiveTabs.Tab {
    return self.inner.newTab(.{
        .content = opts.content,
        .trigger = .{
            .drawFn = drawTrigger,
            .style = .{
                .height = .{ .point = 1 },
                .flex_shrink = 0,
            },
        },
        .userdata = opts.userdata,
    });
}

pub fn select(self: *Tabs, id: ?usize) void {
    self.inner.select(id);
}

pub fn closeTab(self: *Tabs, id: usize) void {
    self.inner.closeTab(id);
}

pub fn getElement(self: *Tabs) *Element {
    return self.inner.container;
}

fn drawList(_: *Element, buffer: *Buffer) void {
    // fill the tab list bar bg
    _ = buffer;
}

fn drawTrigger(element: *Element, buffer: *Buffer) void {
    const theme = global.settings.theme;
    const tabs: *PrimitiveTabs = @ptrCast(@alignCast(element.userdata orelse return));

    // find which tab this trigger belongs to
    for (tabs.values.items) |tab| {
        if (tab.trigger == element) {
            const is_selected = tabs.selected != null and tabs.selected.? == tab.id;
            const bg = if (is_selected) theme.primaryBg else theme.bg;
            const fg = if (is_selected) theme.primaryFg else theme.mutedFg;

            element.fill(buffer, .{ .style = .{ .bg = bg, .fg = fg } });
            // print tab label via userdata or a fixed label
            break;
        }
    }
}
