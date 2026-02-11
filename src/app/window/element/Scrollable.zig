const std = @import("std");
const vaxis = @import("vaxis");
const Element = @import("mod.zig");
const Buffer = @import("../../Buffer.zig");
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
track: vaxis.Color,
thumb: vaxis.Color,

scroll_x: i32 = 0,
scroll_y: i32 = 0,

drag_start_y_pixel: ?i32 = null,
drag_start_scroll_y: i32 = 0,

mode: ScrollMode = .vertical,

const Options = struct {
    mode: ScrollMode = .vertical,
    bar: bool = true,
    track: vaxis.Color = .default,
    thumb: vaxis.Color = .default,
    outer: Element.Style,
};

pub fn init(alloc: Allocator, opts: Options) !*Scrollable {
    const self = try alloc.create(Scrollable);

    var style = opts.outer;

    style.overflow = .scroll;

    const outer = try alloc.create(Element);
    outer.* = Element.init(alloc, .{
        .style = style,
        .beforeDrawFn = beforeDrawFn,
        .afterDrawFn = afterDrawFn,
        .beforeHitFn = beforeHitFn,
        .hitFn = hitGridFn,
        .afterHitFn = afterHitFn,
        .userdata = self,
    });

    try outer.addEventListener(.wheel, onWheel);
    try outer.addEventListener(.mouse_over, mouseOver);
    try outer.addEventListener(.mouse_out, mouseOut);
    try outer.addEventListener(.drag, onDraw);

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
        .thumb = opts.thumb,
        .track = opts.track,
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
            .visible = false,
            .drawFn = drawBar,
            .zIndex = 10,
            .userdata = self,
            .hitFn = Element.hitSelf,
        });

        self.bar = bar;

        try bar.addEventListener(.click, onBarClick);
        try bar.addEventListener(.drag, onBarDrag);
        try bar.addEventListener(.drag_end, onBarDragEnd);

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

pub fn mouseOver(element: *Element, _: Element.EventData) void {
    const self: *Scrollable = @ptrCast(@alignCast(element.userdata));
    if (self.bar) |bar| {
        if (!bar.visible) {
            bar.visible = true;
            element.context.?.requestDraw();
        }
    }
}

pub fn mouseOut(element: *Element, _: Element.EventData) void {
    const self: *Scrollable = @ptrCast(@alignCast(element.userdata));
    if (self.bar) |bar| {
        if (bar.visible and !bar.dragging) {
            bar.visible = false;
            element.context.?.requestDraw();
        }
    }
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

    if (outer > inner) return 0;

    return @intCast(inner - outer);
}

pub const RowSpan = struct { start: usize, end: usize };

pub fn visibleRowSpan(self: *const Scrollable, child: *const Element) RowSpan {
    const child_offset: i32 = @intCast(child.node.getLayoutTop());
    const child_height: i32 = @intCast(child.layout.height);
    const vp_height: i32 = @intCast(self.outer.layout.height);

    const start: i32 = @max(0, self.scroll_y - child_offset);
    const end: i32 = @min(child_height, self.scroll_y - child_offset + vp_height);
    if (end <= start) return .{ .start = 0, .end = 0 };

    return .{
        .start = @intCast(start),
        .end = @intCast(end),
    };
}

pub fn childRowFromScreenY(self: *const Scrollable, child: *const Element, screen_row: u16) ?usize {
    const child_offset: i32 = @intCast(child.node.getLayoutTop());
    const child_height: i32 = @intCast(child.layout.height);
    const vp_top: i32 = @intCast(self.outer.layout.top);

    const vp_row: i32 = @as(i32, @intCast(screen_row)) - vp_top;
    if (vp_row < 0) return null;

    const content_row: i32 = vp_row + self.scroll_y - child_offset;
    if (content_row < 0) return null;
    if (content_row >= child_height) return null;
    return @intCast(content_row);
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

const SCROLL_STEP: i32 = 1;

fn onWheel(element: *Element, data: Element.EventData) void {
    const self: *Scrollable = @ptrCast(@alignCast(element.userdata));
    const mouse = data.wheel.mouse;

    const dx: i32 = switch (mouse.button) {
        .wheel_left => -SCROLL_STEP,
        .wheel_right => SCROLL_STEP,
        else => 0,
    };

    const dy: i32 = switch (mouse.button) {
        .wheel_up => -SCROLL_STEP,
        .wheel_down => SCROLL_STEP,
        else => 0,
    };

    self.scrollBy(dx, dy);

    if (element.context) |ctx| {
        ctx.requestDraw();
    }
}

fn withAlpha(color: vaxis.Color, alpha: f32) vaxis.Color {
    return color.setAlpha(alpha);
}

const lower_blocks = [8][]const u8{ " ", "▁", "▂", "▃", "▄", "▅", "▆", "▇" };
const upper_blocks = [8][]const u8{ " ", "▔", "🮂", "🮃", "▀", "🮄", "🮅", "🮆" };

fn drawBar(element: *Element, buffer: *Buffer) void {
    const self: *Scrollable = @ptrCast(@alignCast(element.userdata));
    const bar_height = element.layout.height;
    const content_height = self.inner.layout.height;
    const viewport_height = self.outer.layout.height;

    if (content_height == 0 or bar_height == 0 or viewport_height >= content_height) return;

    const bar_height_eighths: u32 = @as(u32, bar_height) * 8;
    const thumb_height_eighths: u32 = @max(8, (@as(u32, viewport_height) * bar_height_eighths) / content_height);

    const max_scroll = self.maxScrollY();
    const scroll_range_eighths: u32 = bar_height_eighths - thumb_height_eighths;
    const curr: u32 = if (self.scroll_y < 0) 0 else @intCast(self.scroll_y);
    const thumb_pos_eighths: u32 = if (max_scroll > 0) (curr * scroll_range_eighths) / @as(u32, @intCast(max_scroll)) else 0;

    const alpha: f32 = if (element.hovered or element.dragging) 1.0 else 0.5;
    const track_color = withAlpha(self.track, alpha);
    const thumb_color = withAlpha(self.thumb, alpha);

    element.fill(buffer, .{ .style = .{ .bg = track_color } });

    const top_cell = thumb_pos_eighths / 8;
    const top_frac = thumb_pos_eighths % 8;
    const thumb_end_eighths = thumb_pos_eighths + thumb_height_eighths;
    const bottom_cell = thumb_end_eighths / 8;
    const bottom_frac = thumb_end_eighths % 8;

    const bar_left = element.layout.left;
    const bar_top = element.layout.top;

    if (top_cell == bottom_cell) {
        const char = lower_blocks[bottom_frac];
        buffer.writeCell(bar_left, bar_top + @as(u16, @intCast(top_cell)), .{
            .char = .{ .grapheme = char },
            .style = .{ .fg = thumb_color, .bg = track_color },
        });
    } else {
        if (top_frac > 0) {
            const char = lower_blocks[8 - top_frac];
            buffer.writeCell(bar_left, bar_top + @as(u16, @intCast(top_cell)), .{
                .char = .{ .grapheme = char },
                .style = .{ .fg = thumb_color, .bg = .{ .rgba = .{ 0, 0, 0, 0 } } },
            });
        }

        const start_full = top_cell + if (top_frac > 0) @as(u32, 1) else @as(u32, 0);
        const end_full = bottom_cell;
        if (end_full > start_full) {
            buffer.fillRect(
                bar_left,
                bar_top + @as(u16, @intCast(start_full)),
                1,
                @intCast(end_full - start_full),
                .{ .style = .{ .bg = thumb_color } },
            );
        }

        if (bottom_frac > 0 and bottom_cell < bar_height) {
            const char = upper_blocks[bottom_frac];
            buffer.writeCell(bar_left, bar_top + @as(u16, @intCast(bottom_cell)), .{
                .char = .{ .grapheme = char },
                .style = .{ .fg = thumb_color, .bg = .{ .rgba = .{ 0, 0, 0, 0 } } },
            });
        }
    }
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
    const bar_top: i32 = @intCast(element.layout.top);
    const click_y: u16 = @intCast(@max(0, @as(i32, mouse.row) - bar_top));

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

fn onDraw(_: *Element, data: Element.EventData) void {
    const ctx = data.drag.ctx;
    if (ctx.phase == .at_target) ctx.stopPropagation();
}

fn onBarDrag(element: *Element, data: Element.EventData) void {
    const self: *Scrollable = @ptrCast(@alignCast(element.userdata));
    const mouse = data.drag.mouse;
    const ctx = element.context orelse return;
    const size = ctx.app.window.size;

    data.drag.ctx.stopPropagation();

    const current_y_pixel: i32 = mouse.pixel_row;

    if (self.drag_start_y_pixel == null) {
        self.drag_start_y_pixel = current_y_pixel;
        self.drag_start_scroll_y = self.scroll_y;
    }

    const cell_height_pixels: i32 = @intCast(size.y_pixel / size.rows);
    const eighth_pixels: i32 = @max(1, @divFloor(cell_height_pixels, 8));

    const delta_pixels = current_y_pixel - self.drag_start_y_pixel.?;
    const delta_eighths = @divFloor(delta_pixels, eighth_pixels);

    const bar_height = element.layout.height;
    const content_height = self.inner.layout.height;
    const viewport_height = self.outer.layout.height;

    if (content_height <= viewport_height) return;

    const thumb_height: u16 = @max(1, @as(u16, @intCast((@as(u32, viewport_height) * bar_height) / content_height)));
    const thumb_travel_eighths: i32 = @as(i32, bar_height - thumb_height) * 8;
    const max_scroll = self.maxScrollY();

    if (thumb_travel_eighths > 0) {
        const scroll_delta = @divFloor(delta_eighths * max_scroll, thumb_travel_eighths);
        const new_scroll = self.drag_start_scroll_y + scroll_delta;
        self.scrollTo(0, new_scroll);
    }

    ctx.requestDraw();
}

fn onBarDragEnd(element: *Element, _: Element.EventData) void {
    const self: *Scrollable = @ptrCast(@alignCast(element.userdata));
    self.drag_start_y_pixel = null;

    if (!self.outer.hovered and !self.bar.?.hovered) {
        self.bar.?.visible = false;
    }

    if (element.context) |ctx| {
        ctx.requestDraw();
    }
}
