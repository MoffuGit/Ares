pub const Element = @This();

const std = @import("std");
const vaxis = @import("vaxis");

const Buffer = @import("../Buffer.zig");
pub const Childrens = std.ArrayList(Element);

visible: bool = true,
dirty: bool = false,
zIndex: usize = 0,
destroyed: bool = false,
opacity: f32 = 1.0,
childrens: ?Childrens = null,
buffer: ?Buffer = null,
x: u16 = 0,
y: u16 = 0,
width: u16 = 0,
height: u16 = 0,

userdata: ?*anyopaque = null,
//Callbacks for different events
updateFn: ?*const fn (userdata: ?*anyopaque, time: std.time.Instant) void = null,
drawFn: ?*const fn (userdata: ?*anyopaque, buffer: *Buffer) void = null,
//MouseHandler, KeyHanlder...

pub fn draw(self: *Element, buffer: *Buffer) !void {
    if (self.drawFn) |callback| {
        callback(self.userdata, buffer);
    }
}

pub fn update(self: *Element) !void {
    if (self.updateFn) |callback| {
        callback(self.userdata, try std.time.Instant.now());
    }
}
