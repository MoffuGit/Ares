pub const Root = @This();

const Element = @import("Element.zig");
const Timer = @import("mod.zig").Timer;
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

pub fn init(alloc: std.mem.Allocator) Root {
    return .{
        .element = Element.init(alloc),
    };
}

pub fn setup(self: *Root) !void {
    self.element.userdata = self;
    self.element.updateFn = update;
    self.element.drawFn = draw;

    const now = std.time.microTimestamp();
    try self.element.addTimer(.{
        .next = now + 10_000,
        .callback = tickRed,
        .userdata = self,
    });
    try self.element.addTimer(.{
        .next = now + 15_000,
        .callback = tickGreen,
        .userdata = self,
    });
    try self.element.addTimer(.{
        .next = now + 20_000,
        .callback = tickBlue,
        .userdata = self,
    });
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

pub fn tickRed(userdata: ?*anyopaque, time: i64) ?Timer {
    if (userdata == null) return null;
    const root: *Root = @ptrCast(@alignCast(userdata));

    updateChannel(&root.red, &root.red_dir);
    root.bg = .{ .rgba = .{ root.red, root.green, root.blue, 255 } };
    root.element.requestDraw() catch {};

    return Timer{
        .next = time + 10_000,
        .callback = tickRed,
        .userdata = userdata,
    };
}

pub fn tickGreen(userdata: ?*anyopaque, time: i64) ?Timer {
    if (userdata == null) return null;
    const root: *Root = @ptrCast(@alignCast(userdata));

    updateChannel(&root.green, &root.green_dir);
    root.bg = .{ .rgba = .{ root.red, root.green, root.blue, 255 } };
    root.element.requestDraw() catch {};

    return Timer{
        .next = time + 15_000,
        .callback = tickGreen,
        .userdata = userdata,
    };
}

pub fn tickBlue(userdata: ?*anyopaque, time: i64) ?Timer {
    if (userdata == null) return null;
    const root: *Root = @ptrCast(@alignCast(userdata));

    updateChannel(&root.blue, &root.blue_dir);
    root.bg = .{ .rgba = .{ root.red, root.green, root.blue, 255 } };
    root.element.requestDraw() catch {};

    return Timer{
        .next = time + 20_000,
        .callback = tickBlue,
        .userdata = userdata,
    };
}
