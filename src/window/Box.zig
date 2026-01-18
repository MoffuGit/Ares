pub const Box = @This();

const std = @import("std");
const vaxis = @import("vaxis");
const Element = @import("Element.zig");
const Animation = @import("mod.zig").Animation;
const Buffer = @import("../Buffer.zig");

element: Element,

start_x: f32 = 0,
end_x: f32 = 40,
current_x: f32 = 0,

start_y: f32 = 0,
end_y: f32 = 10,
current_y: f32 = 0,

color: vaxis.Color = .{ .rgb = .{ 255, 100, 100 } },
box_width: u16 = 10,
box_height: u16 = 5,

move_animation: Animation = undefined,

pub fn init(alloc: std.mem.Allocator) Box {
    return .{
        .element = Element.init(alloc),
    };
}

pub fn setup(self: *Box) !void {
    self.element.userdata = self;
    self.element.drawFn = draw;

    self.move_animation = .{
        .duration_us = 2_000_000,
        .callback = onMove,
        .userdata = self,
        .easing = .ease_out_elastic,
        .repeat = true,
    };

    try self.element.startAnimation(&self.move_animation);
}

fn draw(userdata: ?*anyopaque, buffer: *Buffer) void {
    const self: *Box = @ptrCast(@alignCast(userdata orelse return));

    const x: u16 = @intFromFloat(@max(0, self.current_x));
    const y: u16 = @intFromFloat(@max(0, self.current_y));

    var row: u16 = 0;
    while (row < self.box_height) : (row += 1) {
        var col: u16 = 0;
        while (col < self.box_width) : (col += 1) {
            const px = x + col;
            const py = y + row;
            if (px < buffer.width and py < buffer.height) {
                buffer.writeCell(px, py, .{ .style = .{ .bg = self.color } });
            }
        }
    }
}

fn onMove(userdata: ?*anyopaque, progress: f32) void {
    const self: *Box = @ptrCast(@alignCast(userdata orelse return));

    self.current_x = lerp(self.start_x, self.end_x, progress);
    self.current_y = lerp(self.start_y, self.end_y, progress);

    self.element.requestDraw() catch {};
}

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}
