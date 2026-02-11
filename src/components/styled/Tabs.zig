const std = @import("std");
const lib = @import("../../lib.zig");
const global = @import("../../global.zig");

const PrimitiveTabs = @import("../primitives/Tabs.zig");
const Element = lib.Element;
const Buffer = lib.Buffer;
const Allocator = std.mem.Allocator;
const Settings = @import("../../settings/mod.zig");

pub const Style = enum {
    underline,
    block,
    minimal,
};

pub fn Tabs(comptime style: Style) type {
    _ = style;
    return struct {
        const Self = @This();

        inner: *PrimitiveTabs,

        pub fn init(alloc: Allocator) !Self {
            return .{
                .inner = try PrimitiveTabs.create(alloc, .{
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
                            .align_self = .flex_end,
                            .width = .auto,
                            .height = .auto,
                            .direction = .ltr,
                            // .gap = .{
                            //     .column = .{
                            //         .point = 1,
                            //     },
                            // },
                            .flex_direction = .row,
                            .flex_shrink = 0,
                        },
                    },
                }),
            };
        }

        pub fn deinit(self: *Self) void {
            self.inner.destroy();
        }

        pub fn newTab(self: *Self, opts: struct {
            content: Element.Options = .{},
            userdata: ?*anyopaque = null,
        }) !*PrimitiveTabs.Tab {
            return self.inner.newTab(.{
                .content = opts.content,
                .trigger = .{
                    .drawFn = drawTrigger,
                    .style = .{
                        .height = .{ .point = 1 },
                        .width = .{ .point = 1 },
                        .flex_shrink = 0,
                    },
                    .hitFn = Element.hitSelf,
                },
                .userdata = opts.userdata,
            });
        }

        pub fn select(self: *Self, id: ?usize) void {
            self.inner.select(id);
        }

        pub fn closeTab(self: *Self, id: usize) void {
            self.inner.closeTab(id);
        }

        pub fn getElement(self: *Self) *Element {
            return self.inner.container;
        }

        fn drawList(_: *Element, buffer: *Buffer) void {
            _ = buffer;
        }

        fn drawTrigger(element: *Element, buffer: *Buffer) void {
            const theme = global.settings.theme;
            const self: *PrimitiveTabs.Tab = @ptrCast(@alignCast(element.userdata orelse return));
            if (self.id == self.tabs.selected) {
                _ = element.print(buffer, &.{
                    .{ .text = "┃", .style = .{ .fg = theme.mutedBg } },
                }, .{});
            } else {
                _ = element.print(buffer, &.{
                    .{ .text = "❙", .style = .{ .fg = theme.mutedBg } },
                }, .{});
            }
        }
    };
}
