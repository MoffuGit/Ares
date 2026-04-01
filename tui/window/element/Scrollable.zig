const std = @import("std");
const vaxis = @import("vaxis");
const ElementMod = @import("mod.zig");
const Buffer = @import("../../Buffer.zig");
const HitGrid = @import("../HitGrid.zig");
const Allocator = std.mem.Allocator;

pub const Scrollable = @This();
const Element = ElementMod.Element;
const Registry = std.AutoHashMap(u64, *Scrollable);

var registry: ?Registry = null;

pub const ScrollMode = enum {
    vertical,
    horizontal,
    both,
};

outer: *Element,
inner: *Element,
bar: ?*Element = null,
track: vaxis.Color = .{ .rgba = .{ 255, 255, 255, 24 } },
thumb: vaxis.Color = .{ .rgba = .{ 255, 255, 255, 168 } },
scroll_x: i32 = 0,
scroll_y: i32 = 0,
mode: ScrollMode = .vertical,
bar_dragging: bool = false,
bar_drag_offset_eighths: u32 = 0,

pub const Options = struct {
    num: ?u64 = null,
    zIndex: usize = 0,
    mode: ScrollMode = .vertical,
    bar: bool = true,
    track: vaxis.Color = .{ .rgba = .{ 255, 255, 255, 24 } },
    thumb: vaxis.Color = .{ .rgba = .{ 255, 255, 255, 168 } },
    style: ElementMod.Style = .{},
};

pub fn initRegistry(alloc: Allocator) void {
    if (registry != null) return;
    registry = Registry.init(alloc);
}

pub fn deinitRegistry() void {
    if (registry) |*map| {
        map.deinit();
        registry = null;
    }
}

pub fn lookup(id: u64) ?*Scrollable {
    if (registry) |*map| {
        return map.get(id);
    }

    return null;
}

pub fn init(alloc: Allocator, opts: Options) !*Scrollable {
    const self = try alloc.create(Scrollable);
    errdefer alloc.destroy(self);

    const outer = try alloc.create(Element);
    errdefer alloc.destroy(outer);

    const inner = try alloc.create(Element);
    errdefer alloc.destroy(inner);

    const bar = if (opts.bar) try alloc.create(Element) else null;
    errdefer if (bar) |bar_elem| alloc.destroy(bar_elem);

    var style = opts.style;
    style.overflow = .scroll;

    self.* = .{
        .outer = outer,
        .inner = inner,
        .bar = bar,
        .track = opts.track,
        .thumb = opts.thumb,
        .mode = opts.mode,
    };

    outer.* = Element.init(alloc, .{
        .num = opts.num,
        .kind = .scrollable,
        .zIndex = opts.zIndex,
        .style = style,
        .beforeDrawFn = beforeDrawFn,
        .afterDrawFn = afterDrawFn,
        .beforeHitFn = beforeHitFn,
        .hitFn = hitGridFn,
        .afterHitFn = afterHitFn,
        .userdata = self,
    });
    errdefer outer.deinit();

    inner.* = Element.init(alloc, .{
        .style = .{
            .overflow = .visible,
            .flex_shrink = 0,
        },
        .beforeDrawFn = contentBeforeDrawFn,
        .afterDrawFn = contentAfterDrawFn,
        .beforeHitFn = contentBeforeHitFn,
        .afterHitFn = contentAfterHitFn,
        .userdata = self,
    });
    errdefer inner.deinit();

    try outer.addChild(inner);

    if (bar) |bar_elem| {
        bar_elem.* = Element.init(alloc, .{
            .style = .{
                .position_type = .absolute,
                .width = .{ .point = 1 },
                .position = .{ .right = .{ .point = 0 } },
                .height = .{ .percent = 100 },
            },
            .drawFn = drawBar,
            .hitFn = hitBar,
            .zIndex = 10,
            .userdata = self,
        });
        errdefer bar_elem.deinit();

        try outer.addChild(bar_elem);
    }

    try self.register();

    return self;
}

pub fn deinit(self: *Scrollable, alloc: Allocator) void {
    self.unregister();
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

pub fn elem(self: *Scrollable) *Element {
    return self.outer;
}

pub fn content(self: *Scrollable) *Element {
    return self.inner;
}

pub fn addChild(self: *Scrollable, child: *Element) !void {
    try self.inner.addChild(child);
}

pub fn insertChild(self: *Scrollable, child: *Element, index: usize) !void {
    try self.inner.insertChild(child, index);
}

pub fn removeChild(self: *Scrollable, num: u64) void {
    self.inner.removeChild(num);
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
    const next_x = self.clampX(x);
    const next_y = self.clampY(y);

    self.scroll_x = next_x;
    self.scroll_y = next_y;
}

pub fn containsPoint(self: *const Scrollable, col: u16, row: u16) bool {
    const layout = self.outer.layout;
    return col >= layout.left and
        col < layout.left + layout.width and
        row >= layout.top and
        row < layout.top + layout.height;
}

pub fn barPress(self: *Scrollable, col: u16, row: u16) bool {
    const metrics = self.barMetrics() orelse return false;
    if (!metrics.contains(col, row)) return false;

    const pointer_eighths = metrics.pointerEighths(row);
    const thumb_hit = metrics.thumbContainsRow(row);

    self.bar_drag_offset_eighths = if (thumb_hit)
        pointer_eighths - metrics.thumb_pos_eighths
    else
        metrics.thumb_height_eighths / 2;

    if (!thumb_hit) {
        self.setScrollYFromBarPointer(metrics, pointer_eighths);
    }

    self.bar_dragging = true;
    return true;
}

pub fn barDrag(self: *Scrollable, col: u16, row: u16) bool {
    _ = col;

    if (!self.bar_dragging) return false;

    const metrics = self.barMetrics() orelse {
        self.bar_dragging = false;
        return false;
    };

    self.setScrollYFromBarPointer(metrics, metrics.pointerEighths(row));
    return true;
}

pub fn barRelease(self: *Scrollable) bool {
    const was_dragging = self.bar_dragging;
    self.bar_dragging = false;
    return was_dragging;
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
    const outer_width = self.outer.layout.width;
    const inner_width = self.inner.layout.width;

    if (outer_width >= inner_width) return 0;

    return @intCast(inner_width - outer_width);
}

pub fn maxScrollY(self: *const Scrollable) i32 {
    const outer_height = self.outer.layout.height;
    const inner_height = self.inner.layout.height;

    if (outer_height >= inner_height) return 0;

    return @intCast(inner_height - outer_height);
}

fn beforeDrawFn(element: *Element, buffer: *Buffer) void {
    const layout = element.layout;
    buffer.pushClip(layout.left, layout.top, layout.width, layout.height);
}

fn afterDrawFn(_: *Element, buffer: *Buffer) void {
    buffer.popClip();
}

fn beforeHitFn(element: *Element, hit_grid: *HitGrid) void {
    const layout = element.layout;
    hit_grid.pushClip(layout.left, layout.top, layout.width, layout.height);
}

fn hitGridFn(element: *Element, hit_grid: *HitGrid) void {
    const layout = element.layout;
    hit_grid.fillRect(layout.left, layout.top, layout.width, layout.height, element.num);
}

fn hitBar(element: *Element, hit_grid: *HitGrid) void {
    const self: *Scrollable = @ptrCast(@alignCast(element.userdata));
    const metrics = self.barMetrics() orelse return;

    hit_grid.fillRect(metrics.left, metrics.top, metrics.width, metrics.height, self.outer.num);
}

fn afterHitFn(_: *Element, hit_grid: *HitGrid) void {
    hit_grid.popClip();
}

fn contentBeforeDrawFn(element: *Element, buffer: *Buffer) void {
    const self: *Scrollable = @ptrCast(@alignCast(element.userdata));
    buffer.pushOffset(-self.scroll_x, -self.scroll_y);
}

fn contentAfterDrawFn(_: *Element, buffer: *Buffer) void {
    buffer.popOffset();
}

fn contentBeforeHitFn(element: *Element, hit_grid: *HitGrid) void {
    const self: *Scrollable = @ptrCast(@alignCast(element.userdata));
    hit_grid.pushOffset(-self.scroll_x, -self.scroll_y);
}

fn contentAfterHitFn(_: *Element, hit_grid: *HitGrid) void {
    hit_grid.popOffset();
}

fn drawBar(element: *Element, buffer: *Buffer) void {
    const self: *Scrollable = @ptrCast(@alignCast(element.userdata));
    const metrics = self.barMetrics() orelse return;

    element.fill(buffer, .{ .style = .{ .bg = self.track } });

    const top_cell = metrics.thumb_pos_eighths / 8;
    const top_frac = metrics.thumb_pos_eighths % 8;
    const thumb_end_eighths = metrics.thumb_pos_eighths + metrics.thumb_height_eighths;
    const bottom_cell = thumb_end_eighths / 8;
    const bottom_frac = thumb_end_eighths % 8;

    const bar_left = metrics.left;
    const bar_top = metrics.top;

    if (top_cell == bottom_cell) {
        const char = lower_blocks[bottom_frac];
        buffer.writeCell(bar_left, bar_top + @as(u16, @intCast(top_cell)), .{
            .char = .{ .grapheme = char },
            .style = .{ .fg = self.thumb, .bg = self.track },
        });
        return;
    }

    if (top_frac > 0) {
        const char = lower_blocks[8 - top_frac];
        buffer.writeCell(bar_left, bar_top + @as(u16, @intCast(top_cell)), .{
            .char = .{ .grapheme = char },
            .style = .{ .fg = self.thumb, .bg = self.track },
        });
    }

    const start_full = top_cell + if (top_frac > 0) @as(u32, 1) else @as(u32, 0);
    const end_full = @min(bottom_cell, @as(u32, metrics.height));
    if (end_full > start_full) {
        buffer.fillRect(
            bar_left,
            bar_top + @as(u16, @intCast(start_full)),
            1,
            @intCast(end_full - start_full),
            .{ .style = .{ .bg = self.thumb } },
        );
    }

    if (bottom_frac > 0 and bottom_cell < metrics.height) {
        const char = upper_blocks[bottom_frac];
        buffer.writeCell(bar_left, bar_top + @as(u16, @intCast(bottom_cell)), .{
            .char = .{ .grapheme = char },
            .style = .{ .fg = self.thumb, .bg = self.track },
        });
    }
}

const BarMetrics = struct {
    left: u16,
    top: u16,
    width: u16,
    height: u16,
    bar_height_eighths: u32,
    thumb_height_eighths: u32,
    thumb_pos_eighths: u32,
    scroll_range_eighths: u32,
    max_scroll: u32,

    fn contains(self: BarMetrics, col: u16, row: u16) bool {
        return col >= self.left and
            col < self.left + self.width and
            row >= self.top and
            row < self.top + self.height;
    }

    fn pointerEighths(self: BarMetrics, row: u16) u32 {
        if (row <= self.top) return 0;

        const last_row = self.top + self.height - 1;
        if (row >= last_row) return self.bar_height_eighths;

        return (@as(u32, row - self.top) * 8) + 4;
    }

    fn thumbContainsRow(self: BarMetrics, row: u16) bool {
        if (row < self.top or row >= self.top + self.height) return false;

        const cell_start = @as(u32, row - self.top) * 8;
        const cell_end = cell_start + 8;
        const thumb_end = self.thumb_pos_eighths + self.thumb_height_eighths;

        return cell_start < thumb_end and cell_end > self.thumb_pos_eighths;
    }
};

fn barMetrics(self: *const Scrollable) ?BarMetrics {
    if (self.mode == .horizontal) return null;

    const bar = self.bar orelse return null;
    const content_height = self.inner.layout.height;
    const viewport_height = self.outer.layout.height;
    const bar_height = bar.layout.height;
    const max_scroll = self.maxScrollY();

    if (content_height == 0 or bar_height == 0 or viewport_height == 0) return null;
    if (viewport_height >= content_height or max_scroll <= 0) return null;

    const bar_height_eighths: u32 = @as(u32, bar_height) * 8;
    const thumb_height_eighths: u32 = @max(8, (@as(u32, viewport_height) * bar_height_eighths) / content_height);
    const scroll_range_eighths: u32 = bar_height_eighths - thumb_height_eighths;
    const current_scroll: u32 = if (self.scroll_y < 0) 0 else @intCast(self.scroll_y);
    const max_scroll_u32: u32 = @intCast(max_scroll);
    const thumb_pos_eighths: u32 = if (scroll_range_eighths > 0)
        (current_scroll * scroll_range_eighths) / max_scroll_u32
    else
        0;

    return .{
        .left = bar.layout.left,
        .top = bar.layout.top,
        .width = bar.layout.width,
        .height = bar.layout.height,
        .bar_height_eighths = bar_height_eighths,
        .thumb_height_eighths = thumb_height_eighths,
        .thumb_pos_eighths = thumb_pos_eighths,
        .scroll_range_eighths = scroll_range_eighths,
        .max_scroll = max_scroll_u32,
    };
}

fn setScrollYFromBarPointer(self: *Scrollable, metrics: BarMetrics, pointer_eighths: u32) void {
    if (metrics.max_scroll == 0 or metrics.scroll_range_eighths == 0) {
        self.scroll_y = 0;
        return;
    }

    const raw_thumb_pos = @as(i64, pointer_eighths) - @as(i64, self.bar_drag_offset_eighths);
    const clamped_thumb_pos: u32 = if (raw_thumb_pos <= 0)
        0
    else if (raw_thumb_pos >= metrics.scroll_range_eighths)
        metrics.scroll_range_eighths
    else
        @intCast(raw_thumb_pos);

    const scroll_y = (@as(u64, clamped_thumb_pos) * metrics.max_scroll) / metrics.scroll_range_eighths;
    self.scroll_y = self.clampY(@intCast(scroll_y));
}

const lower_blocks = [9][]const u8{ " ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" };
const upper_blocks = [9][]const u8{ " ", "▔", "🮂", "🮃", "▀", "🮄", "🮅", "🮆", "█" };

fn register(self: *Scrollable) !void {
    if (registry) |*map| {
        try map.put(self.outer.num, self);
    }
}

fn unregister(self: *Scrollable) void {
    if (registry) |*map| {
        _ = map.remove(self.outer.num);
    }
}

const testing = std.testing;

test "scrollbar drag updates vertical scroll" {
    const alloc = testing.allocator;
    const scrollable = try Scrollable.init(alloc, .{});
    defer scrollable.deinit(alloc);

    scrollable.outer.layout = .{ .left = 0, .top = 0, .width = 10, .height = 10 };
    scrollable.inner.layout = .{ .left = 0, .top = 0, .width = 10, .height = 100 };
    scrollable.bar.?.layout = .{ .left = 9, .top = 0, .width = 1, .height = 10 };

    try testing.expect(scrollable.barPress(9, 0));
    try testing.expect(scrollable.barDrag(9, 9));
    try testing.expectEqual(scrollable.maxScrollY(), scrollable.scroll_y);
    try testing.expect(scrollable.barRelease());
}
