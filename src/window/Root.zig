pub const Root = @This();

const Element = @import("Element.zig");
const std = @import("std");
const vaxis = @import("vaxis");
const Timer = @import("mod.zig").Timer;

const Buffer = @import("../Buffer.zig");

element: Element = .{},

bg: vaxis.Color = .default,
count: u8 = 0,
direction: enum { up, down } = .up,

pub fn init(self: *Root) !void {
    self.element.userdata = self;
    self.element.updateFn = update;
    self.element.drawFn = draw;
    self.element.tickFn = tick;
    
    // Schedule the first timer for 10ms from now
    const now = std.time.microTimestamp();
    try self.element.scheduleTimer(now + 10_000); // 10ms in microseconds
}

pub fn draw(self: ?*anyopaque, buffer: *Buffer) void {
    if (self == null) return;
    const root: *Root = @ptrCast(@alignCast(self));

    buffer.fill(.{ .style = .{ .bg = root.bg } });
}

pub fn update(self: ?*anyopaque, time: std.time.Instant) void {
    if (self == null) return;
    _ = time;
}

pub fn tick(self: ?*anyopaque, time: i64) ?Timer {
    if (self == null) return null;
    const root: *Root = @ptrCast(@alignCast(self));
    
    // Update red value
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
    
    // Request a redraw
    root.element.requestDraw() catch {};
    
    // Schedule next tick for 10ms from now
    return Timer{
        .next = time + 10_000, // 10ms in microseconds
        .element = &root.element,
    };
}
