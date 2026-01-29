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

outer: Element,
inner: Element,

scroll_x: i32 = 0,
scroll_y: i32 = 0,

content_width: u16 = 0,
content_height: u16 = 0,

mode: ScrollMode = .vertical,

pub fn init(alloc: Allocator, mode: ScrollMode) !*Scrollable {
    const self = try alloc.create(Scrollable);

    const outer = try alloc.create(Element);
    outer.* = Element.init(alloc, .{
        .style = .{
            .overflow = .scroll,
        },
        .beforeDrawFn = beforeDrawFn,
        .afterDrawFn = afterDrawFn,
        .beforeHitFn = beforeHitFn,
        .afterHitFn = afterHitFn,
        .userdata = self,
    });

    const inner = try alloc.create(Element);
    inner.* = Element.init(alloc, .{
        .style = .{
            .overflow = .visible,
        },
    });

    try outer.addChild(inner);

    self.* = Scrollable{
        .outer = outer,
        .inner = inner,
        .mode = mode,
    };

    return self;
}

pub fn deinit(self: *Scrollable, alloc: Allocator) void {
    self.outer.deinit();
    self.inner.deinit();
    alloc.destroy(self.outer);
    alloc.destroy(self.inner);
    alloc.destroy(self);
}

// pub fn scrollBy(self: *Scrollable, dx: i32, dy: i32) void {
//     switch (self.mode) {
//         .vertical => self.scroll_y = self.clampY(self.scroll_y + dy),
//         .horizontal => self.scroll_x = self.clampX(self.scroll_x + dx),
//         .both => {
//             self.scroll_x = self.clampX(self.scroll_x + dx);
//             self.scroll_y = self.clampY(self.scroll_y + dy);
//         },
//     }
// }
//
// pub fn scrollTo(self: *Scrollable, x: i32, y: i32) void {
//     self.scroll_x = self.clampX(x);
//     self.scroll_y = self.clampY(y);
// }
//
// fn clampX(self: *const Scrollable, x: i32) i32 {
//     const max_scroll = self.maxScrollX();
//     if (x < 0) return 0;
//     if (x > max_scroll) return max_scroll;
//     return x;
// }
//
// fn clampY(self: *const Scrollable, y: i32) i32 {
//     const max_scroll = self.maxScrollY();
//     if (y < 0) return 0;
//     if (y > max_scroll) return max_scroll;
//     return y;
// }
//
// pub fn maxScrollX(self: *const Scrollable) i32 {
//     const viewport_width = self.outer.layout.width;
//     if (self.content_width <= viewport_width) return 0;
//     return @as(i32, self.content_width) - @as(i32, viewport_width);
// }
//
// pub fn maxScrollY(self: *const Scrollable) i32 {
//     const viewport_height = self.outer.layout.height;
//     if (self.content_height <= viewport_height) return 0;
//     return @as(i32, self.content_height) - @as(i32, viewport_height);
// }
//
// pub fn updateContentSize(self: *Scrollable) void {
//     var max_right: u16 = 0;
//     var max_bottom: u16 = 0;
//
//     if (self.outer.childrens) |*childrens| {
//         for (childrens.by_order.items) |child| {
//             const child_right = child.layout.left + child.layout.width;
//             const child_bottom = child.layout.top + child.layout.height;
//
//             if (child_right > max_right) max_right = child_right;
//             if (child_bottom > max_bottom) max_bottom = child_bottom;
//         }
//     }
//
//     const parent_left = self.outer.layout.left;
//     const parent_top = self.outer.layout.top;
//
//     self.content_width = if (max_right > parent_left) max_right - parent_left else 0;
//     self.content_height = if (max_bottom > parent_top) max_bottom - parent_top else 0;
//
//     self.scroll_x = self.clampX(self.scroll_x);
//     self.scroll_y = self.clampY(self.scroll_y);
// }

fn beforeDrawFn(element: *Element, buffer: *Buffer) void {
    const layout = element.layout;

    buffer.pushClip(layout.left, layout.top, layout.width, layout.height);
}

//NOTE:
//update the inner left and top values,
//then, call syncLayout for his childrens with recursion
fn calculateLayout(element: *Element) void {
    //take values from outer,
    //update inner
    //update childrens of inner
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

fn afterHitFn(_: *Element, hit_grid: *HitGrid) void {
    defer hit_grid.popClip();
}
