pub const Root = @This();

const Element = @import("Element.zig");
const std = @import("std");
const vaxis = @import("vaxis");

element: Element = .{},

bg: vaxis.Color = .default,
count: u8 = 0,
direction: enum { up, down } = .up,

pub fn init(self: *Root) !void {
    self.element.userdata = self;
    self.element.updateFn = update;
    self.element.drawFn = draw;
}

pub fn draw(self: ?*anyopaque, buffer: []vaxis.Cell) void {
    if (self == null) return;
    const root: *Root = @ptrCast(@alignCast(self));

    const cell: vaxis.Cell = .{ .style = .{ .bg = root.bg } };
    @memset(buffer, cell);
}

pub fn update(self: ?*anyopaque, time: std.time.Instant) void {
    if (self == null) return;
    _ = time;
    const root: *Root = @ptrCast(@alignCast(self));
    switch (root.direction) {
        .up => {
            root.count += 1;
            if (root.count == 255) {
                root.direction = .down;
            }
        },
        .down => {
            root.count -= 1;
            if (root.count == 0) {
                root.direction = .up;
            }
        },
    }
    root.bg = .{ .rgba = .{ root.count, 0, 0, 0 } };
}
