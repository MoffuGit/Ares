pub const Element = @This();

const std = @import("std");
const vaxis = @import("vaxis");

const Timer = @import("mod.zig").Timer;
const Buffer = @import("../Buffer.zig");
pub const Childrens = std.ArrayList(Element);
const Mailbox = @import("Thread.zig").Mailbox;
const xev = @import("../global.zig").xev;

pub const Context = struct {
    mailbox: *Mailbox,
    wakeup: xev.Async,
};

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
context: ?Context = null,
//Callbacks for different events
updateFn: ?*const fn (userdata: ?*anyopaque, time: std.time.Instant) void = null,
drawFn: ?*const fn (userdata: ?*anyopaque, buffer: *Buffer) void = null,
tickFn: ?*const fn (userdata: ?*anyopaque, time: i64) ?Timer = null,
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

pub fn tick(self: *Element, time: i64) !?Timer {
    if (self.tickFn) |callback| {
        return callback(self.userdata, time);
    }

    return null;
}

pub fn scheduleTimer(self: *Element, next: i64) !void {
    if (self.context) |ctx| {
        _ = ctx.mailbox.push(.{ .timer = .{ .next = next, .element = self } }, .instant);
        try ctx.wakeup.notify();
    }
}

pub fn requestDraw(self: *Element) !void {
    if (self.context) |ctx| {
        try ctx.wakeup.notify();
    }
}
