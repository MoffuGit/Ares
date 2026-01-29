const std = @import("std");
const Element = @import("mod.zig").Element;
const Buffer = @import("../Buffer.zig");
const HitGrid = @import("../HitGrid.zig");
const Allocator = std.mem.Allocator;

pub const Scrollable = @This();

pub const ScrollMode = enum {
    vertical,
    horizontal,
    both,
};

outer: *Element,
inner: *Element,
bar: ?*Element = null,

scroll_x: i32 = 0,
scroll_y: i32 = 0,

mode: ScrollMode = .vertical,

const Options = struct {
    mode: ScrollMode = .vertical,
    bar: bool = true,
};

pub fn init(alloc: Allocator, opts: Options) !*Scrollable {
    const self = try alloc.create(Scrollable);

    const outer = try alloc.create(Element);
    outer.* = Element.init(alloc, .{
        .style = .{
            .overflow = .scroll,
            .height = .{ .percent = 100 },
            .width = .{ .percent = 100 },
            .margin = if (!opts.bar) .{} else .{
                .right = .{
                    .point = 1,
                },
            },
        },
        .beforeDrawFn = beforeDrawFn,
        .afterDrawFn = afterDrawFn,
        .beforeHitFn = beforeHitFn,
        .hitFn = hitGridFn,
        .afterHitFn = afterHitFn,
        .userdata = self,
    });

    try outer.addEventListener(.wheel, onWheel);

    const inner = try alloc.create(Element);
    inner.* = Element.init(alloc, .{
        .style = .{
            .overflow = .visible,
            .flex_shrink = 0,
        },
    });

    try outer.addChild(inner);

    self.* = Scrollable{
        .outer = outer,
        .inner = inner,
        .mode = opts.mode,
    };

    if (opts.bar) {
        const bar = try alloc.create(Element);
        bar.* = Element.init(alloc, .{
            .style = .{
                .position_type = .absolute,
                .width = .{
                    .point = 1,
                },
                .position = .{ .right = .{ .point = 0 } },
                .height = .{ .percent = 100 },
            },
            .drawFn = drawBar,
            .zIndex = 10,
            .userdata = self,
            .hitFn = HitGrid.hitElement,
        });

        self.bar = bar;

        try bar.addEventListener(.click, onBarClick);
        try bar.addEventListener(.drag, onBarDrag);

        try outer.addChild(bar);
    }

    return self;
}

pub fn deinit(self: *Scrollable, alloc: Allocator) void {
    if (self.bar) |bar| {
        bar.deinit();
        alloc.destroy(bar);
    }
    self.outer.deinit();
    self.inner.deinit();
    alloc.destroy(self.outer);
    alloc.destroy(self.inner);
    alloc.destroy(self);
}

pub fn scrollBy(self: *Scrollable, dx: i32, dy: i32) void {
    switch (self.mode) {
        .vertical => self.scroll_y = self.clampY(self.scroll_y + dy),
        .horizontal => self.scroll_x = self.clampX(self.scroll_x + dx),
        .both => {
            self.scroll_x = self.clampX(self.scroll_x + dx);
            self.scroll_y = self.clampY(self.scroll_y + dy);
        },
    }
}

pub fn scrollTo(self: *Scrollable, x: i32, y: i32) void {
    self.scroll_x = self.clampX(x);
    self.scroll_y = self.clampY(y);
}

fn clampX(self: *const Scrollable, x: i32) i32 {
    const max_scroll = self.maxScrollX();
    if (x < 0) return 0;
    if (x > max_scroll) return max_scroll;
    return x;
}

fn clampY(self: *const Scrollable, y: i32) i32 {
    const max_scroll = self.maxScrollY();
    if (y < 0) return 0;
    if (y > max_scroll) return max_scroll;
    return y;
}

pub fn maxScrollX(self: *const Scrollable) i32 {
    const outer = self.outer.layout.width;
    const inner = self.inner.layout.width;

    if (outer > inner) return @intCast(outer);

    return @intCast(inner - outer);
}

pub fn maxScrollY(self: *const Scrollable) i32 {
    const outer = self.outer.layout.height;
    const inner = self.inner.layout.height;

    if (outer > inner) return @intCast(outer);

    return @intCast(inner - outer);
}

fn beforeDrawFn(element: *Element, buffer: *Buffer) void {
    const layout = element.layout;

    buffer.pushClip(layout.left, layout.top, layout.width, layout.height);
}

fn calculateLayout(element: *Element) void {
    const self: *Scrollable = @ptrCast(@alignCast(element.userdata));
    const outer = self.outer;
    const inner = self.inner;

    inner.layout.left = subtractOffset(outer.layout.left, self.scroll_x);
    inner.layout.top = subtractOffset(outer.layout.top, self.scroll_y);

    applyLayout(inner);
}

fn applyLayout(parent: *Element) void {
    if (parent.childrens) |*childrens| {
        for (childrens.by_order.items) |child| {
            child.layout.left = parent.layout.left + child.node.getLayoutLeft();
            child.layout.top = parent.layout.top + child.node.getLayoutTop();

            applyLayout(child);
        }
    }
}

fn subtractOffset(pos: u16, offset: i32) u16 {
    const result = @as(i32, pos) - offset;
    if (result < 0) return 0;
    if (result > std.math.maxInt(u16)) return std.math.maxInt(u16);
    return @intCast(result);
}

fn afterDrawFn(_: *Element, buffer: *Buffer) void {
    buffer.popClip();
}

fn beforeHitFn(element: *Element, hit_grid: *HitGrid) void {
    calculateLayout(element);

    const layout = element.layout;

    hit_grid.pushClip(layout.left, layout.top, layout.width, layout.height);
}

fn hitGridFn(element: *Element, hit_grid: *HitGrid) void {
    const layout = element.layout;

    hit_grid.fillRect(layout.left, layout.top, layout.width, layout.height, element.num);
}

fn afterHitFn(_: *Element, hit_grid: *HitGrid) void {
    hit_grid.popClip();
}

const scroll_step: i32 = 3;

fn onWheel(element: *Element, data: Element.EventData) void {
    const self: *Scrollable = @ptrCast(@alignCast(element.userdata));
    const mouse = data.wheel.mouse;

    const dx: i32 = switch (mouse.button) {
        .wheel_left => -scroll_step,
        .wheel_right => scroll_step,
        else => 0,
    };

    const dy: i32 = switch (mouse.button) {
        .wheel_up => -scroll_step,
        .wheel_down => scroll_step,
        else => 0,
    };

    self.scrollBy(dx, dy);

    if (element.context) |ctx| {
        ctx.requestDraw();
    }
}

fn drawBar(element: *Element, buffer: *Buffer) void {
    const self: *Scrollable = @ptrCast(@alignCast(element.userdata));

    const height = element.layout.height;
    const max = self.inner.layout.height;

    if (max == 0 or height == 0) return;

    const curr: u32 = if (self.scroll_y < 0) 0 else @intCast(self.scroll_y);
    const bar_pos: u16 = @intCast((curr * height) / max);

    const char = "▐";

    buffer.fillRect(element.layout.left, element.layout.top, element.layout.width, element.layout.height, .{ .char = .{ .grapheme = char }, .style = .{ .fg = .{ .rgb = .{ 255, 0, 0 } } } });

    buffer.writeCell(element.layout.left, bar_pos, .{ .char = .{ .grapheme = char }, .style = .{ .fg = .{ .rgb = .{ 0, 255, 0 } } } });
}

fn getThumbPos(self: *const Scrollable) u16 {
    const bar = self.bar orelse return 0;
    const height = bar.layout.height;
    const max = self.inner.layout.height;

    if (max == 0 or height == 0) return 0;

    const curr: u32 = if (self.scroll_y < 0) 0 else @intCast(self.scroll_y);
    return @intCast((curr * height) / max);
}

fn onBarClick(element: *Element, data: Element.EventData) void {
    const self: *Scrollable = @ptrCast(@alignCast(element.userdata));
    const mouse = data.click.mouse;

    const thumb_pos = self.getThumbPos();
    const bar_top: i16 = @intCast(element.layout.top);
    const click_y: u16 = @intCast(@max(0, mouse.row - bar_top));

    if (click_y != thumb_pos) {
        const bar_height = element.layout.height;
        const max_scroll = self.maxScrollY();

        if (bar_height > 0) {
            const new_scroll: i32 = @intCast((@as(u32, click_y) * @as(u32, @intCast(max_scroll))) / bar_height);
            self.scrollTo(0, new_scroll);

            if (element.context) |ctx| {
                ctx.requestDraw();
            }
        }
    }
}

fn onBarDrag(element: *Element, data: Element.EventData) void {
    const self: *Scrollable = @ptrCast(@alignCast(element.userdata));
    const mouse = data.drag.mouse;
    const bar_height = element.layout.height;
    const max_scroll = self.maxScrollY();

    if (bar_height > 0) {
        const bar_top: i16 = @intCast(element.layout.top);
        const drag_y: u16 = @intCast(@max(0, mouse.row - bar_top));
        const new_scroll: i32 = @intCast((@as(u32, drag_y) * @as(u32, @intCast(max_scroll))) / bar_height);
        self.scrollTo(0, new_scroll);
    }

    if (element.context) |ctx| {
        ctx.requestDraw();
    }
}
