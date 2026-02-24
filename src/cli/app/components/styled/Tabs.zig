const std = @import("std");
const tui = @import("tui");
const global = @import("../../global.zig");

const PrimitiveTabs = @import("../primitives/Tabs.zig");
const Element = tui.Element;
const Animation = Element.Animation;
const Buffer = tui.Buffer;
const Context = tui.App.Context;
const Allocator = std.mem.Allocator;

pub const Style = enum {
    underline,
    block,
    minimal,
};

const IndicatorAnim = Animation.Animation(f32);

fn lerpF32(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

fn onAnimUpdate(userdata: ?*anyopaque, value: f32, ctx: *Context) void {
    const inner: *PrimitiveTabs = @ptrCast(@alignCast(userdata orelse return));
    inner.indicator.node.setPosition(.left, .{ .point = value });
    ctx.requestDraw();
}

pub const Tabs = struct {
    const Self = @This();

    inner: *PrimitiveTabs,
    anim: IndicatorAnim,
    selected: ?usize = null,

    const speed_us_per_cell: i64 = 20_000;
    const min_duration_us: i64 = 60_000;
    const max_duration_us: i64 = 200_000;

    fn onSelectChanged(self: *Self, tabs: *PrimitiveTabs, id: ?usize) void {
        if (id) |new_id| {
            const target_index = tabs.indexOf(new_id) orelse return;
            const trigger = tabs.values.items[target_index].trigger;
            const list_left: f32 = @floatFromInt(tabs.list.layout.left);
            const target: f32 = @as(f32, @floatFromInt(trigger.layout.left)) - list_left;
            const current: f32 = @as(f32, @floatFromInt(tabs.indicator.layout.left)) - list_left;

            self.anim.cancel();
            self.anim.start = current;

            const pixel_distance = @abs(current - target);
            const duration = std.math.clamp(
                @as(i64, @intFromFloat(pixel_distance)) * speed_us_per_cell,
                min_duration_us,
                max_duration_us,
            );

            const list_top: f32 = @floatFromInt(tabs.list.layout.top);
            const top: f32 = @as(f32, @floatFromInt(trigger.layout.top)) - list_top;
            tabs.indicator.node.setPosition(.top, .{ .point = top });

            self.anim.end = target;
            self.anim.base.duration_us = duration;
            if (tabs.indicator.context) |ctx| {
                self.anim.play(ctx);
            } else {
                tabs.indicator.node.setPosition(.left, .{ .point = target });
            }
        }
    }

    pub fn create(alloc: Allocator) !*Self {
        const tabs = try alloc.create(Self);
        errdefer alloc.destroy(tabs);

        tabs.* = try Self.init(alloc);

        tabs.inner.userdata = tabs;

        return tabs;
    }

    pub fn destroy(self: *Self) void {
        const alloc = self.inner.alloc;
        self.deinit();
        alloc.destroy(self);
    }

    pub fn init(alloc: Allocator) !Self {
        const inner = try PrimitiveTabs.create(alloc, .{
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
                    .flex_direction = .row,
                    .flex_shrink = 0,
                },
            },
            .indicator = .{
                .id = "tabs-indicator",
                .drawFn = drawIndicator,
                .zIndex = 1,
                .style = .{
                    .position_type = .absolute,
                    .height = .{ .point = 1 },
                    .width = .{ .point = 1 },
                },
            },
        });

        return .{
            .inner = inner,
            .anim = IndicatorAnim.init(.{
                .start = 0,
                .end = 0,
                .duration_us = 150_000,
                .updateFn = lerpF32,
                .callback = onAnimUpdate,
                .userdata = inner,
                .easing = .ease_out_cubic,
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

    pub fn next(self: *Self) void {
        self.inner.selectNext();
    }

    pub fn prev(self: *Self) void {
        self.inner.selectPrev();
    }

    pub fn getElement(self: *Self) *Element {
        return self.inner.container;
    }

    fn drawList(_: *Element, buffer: *Buffer) void {
        _ = buffer;
    }

    fn drawTrigger(element: *Element, buffer: *Buffer) void {
        const theme = global.engine.settings.theme;
        _ = element.print(buffer, &.{
            .{ .text = "❙", .style = .{ .fg = theme.fg.setAlpha(0.5) } },
        }, .{});
    }

    fn drawIndicator(element: *Element, buffer: *Buffer) void {
        const theme = global.engine.settings.theme;
        const tabs: *PrimitiveTabs = @ptrCast(@alignCast(element.userdata orelse return));
        const self: *Self = @ptrCast(@alignCast(tabs.userdata orelse return));

        if (tabs.selected == null) return;

        if (self.selected != tabs.selected) {
            self.onSelectChanged(tabs, tabs.selected);
            self.selected = tabs.selected;
        }

        buffer.writeCell(element.layout.left, element.layout.top, .{
            .char = .{ .grapheme = "🮇" },
            .style = .{ .fg = .{ .rgba = theme.fg.rgba } },
        });
    }
};
