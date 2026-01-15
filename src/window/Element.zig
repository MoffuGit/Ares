pub const Element = @This();

const std = @import("std");
const vaxis = @import("vaxis");

pub const Childrens = std.ArrayList(Element);

visible: bool = true,
dirty: bool = false,
zIndex: usize = 0,
destroyed: bool = false,
opacity: f32 = 1.0,
childrens: ?Childrens = null,
buffer: ?vaxis.Buffer = null,

userdata: ?*anyopaque = null,
//Callbacks for different events
updateFn: ?*const fn (userdata: ?*anyopaque, time: std.time.Instant) void = null,
drawFn: ?*const fn (userdata: ?*anyopaque, buffer: []vaxis.Cell) void = null,
//MouseHandler, KeyHanlder...

pub fn draw(self: *Element, buffer: []vaxis.Cell) !void {
    if (self.drawFn) |callback| {
        callback(self.userdata, buffer);
    }
}

pub fn update(self: *Element) !void {
    if (self.updateFn) |callback| {
        callback(self.userdata, try std.time.Instant.now());
    }
}
