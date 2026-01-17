pub const Root = @This();

const Element = @import("Element.zig");
const Timer = @import("mod.zig").Timer;
const Animation = @import("mod.zig").Animation;
const std = @import("std");
const vaxis = @import("vaxis");

const Buffer = @import("../Buffer.zig");

const Direction = enum { up, down };

element: Element,

bg: vaxis.Color = .default,
red: u8 = 0,
green: u8 = 0,
blue: u8 = 0,
red_dir: Direction = .up,
green_dir: Direction = .up,
blue_dir: Direction = .up,

red_timer: Timer = undefined,
green_timer: Timer = undefined,
blue_timer: Timer = undefined,

pub fn init(alloc: std.mem.Allocator) Root {
    return .{
        .element = Element.init(alloc),
    };
}

pub fn setup(self: *Root) !void {
    self.element.userdata = self;
    self.element.updateFn = update;
    self.element.drawFn = draw;

    self.red_timer = .{
        .interval_us = 10_000,
        .callback = tickRed,
        .userdata = self,
    };
    self.green_timer = .{
        .interval_us = 15_000,
        .callback = tickGreen,
        .userdata = self,
    };
    self.blue_timer = .{
        .interval_us = 20_000,
        .callback = tickBlue,
        .userdata = self,
    };

    try self.element.startTimer(&self.red_timer);
    try self.element.startTimer(&self.green_timer);
    try self.element.startTimer(&self.blue_timer);
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

fn updateChannel(value: *u8, dir: *Direction) void {
    switch (dir.*) {
        .up => {
            value.* += 1;
            if (value.* == 255) dir.* = .down;
        },
        .down => {
            value.* -= 1;
            if (value.* == 0) dir.* = .up;
        },
    }
}

fn tickRed(userdata: ?*anyopaque) void {
    const root: *Root = @ptrCast(@alignCast(userdata orelse return));

    updateChannel(&root.red, &root.red_dir);
    root.bg = .{ .rgba = .{ root.red, root.green, root.blue, 255 } };
    root.element.requestDraw() catch {};
}

fn tickGreen(userdata: ?*anyopaque) void {
    const root: *Root = @ptrCast(@alignCast(userdata orelse return));

    updateChannel(&root.green, &root.green_dir);
    root.bg = .{ .rgba = .{ root.red, root.green, root.blue, 255 } };
    root.element.requestDraw() catch {};
}

fn tickBlue(userdata: ?*anyopaque) void {
    const root: *Root = @ptrCast(@alignCast(userdata orelse return));

    updateChannel(&root.blue, &root.blue_dir);
    root.bg = .{ .rgba = .{ root.red, root.green, root.blue, 255 } };
    root.element.requestDraw() catch {};
}
