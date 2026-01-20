pub const Root = @This();

const Element = @import("Element.zig");
const Timer = @import("Timer.zig");
const std = @import("std");
const vaxis = @import("vaxis");

const Allocator = std.mem.Allocator;

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

pub fn create(alloc: std.mem.Allocator, id: []const u8) !*Root {
    const self = try alloc.create(Root);
    self.* = .{
        .element = try Element.init(alloc, .{
            .id = id,
            .userdata = self,
            .updateFn = update,
            .drawFn = draw,
            .removeFn = remove,
        }),
    };

    self.red_timer = .{
        .interval_us = 16_000,
        .callback = tickRed,
        .userdata = self,
    };
    self.green_timer = .{
        .interval_us = 24_000,
        .callback = tickGreen,
        .userdata = self,
    };
    self.blue_timer = .{
        .interval_us = 32_000,
        .callback = tickBlue,
        .userdata = self,
    };
    return self;
}

pub fn destroy(self: *Root, alloc: Allocator) void {
    self.element.remove();

    alloc.destroy(self);
}

fn remove(element: *Element) void {
    const self: *Root = @ptrCast(@alignCast(element.userdata orelse return));

    self.red_timer.cancel();
    self.green_timer.cancel();
    self.blue_timer.cancel();
}

fn draw(element: *Element, buffer: *Buffer) void {
    const self: *Root = @ptrCast(@alignCast(element.userdata orelse return));
    buffer.fill(.{ .style = .{ .bg = self.bg } });
}

fn update(element: *Element, ctx: Element.Context, time: std.time.Instant) void {
    _ = time;

    const self: *Root = @ptrCast(@alignCast(element.userdata orelse return));

    if (self.red_timer.state == .idle) {
        Element.startTimer(ctx, &self.red_timer) catch {};
        Element.startTimer(ctx, &self.green_timer) catch {};
        Element.startTimer(ctx, &self.blue_timer) catch {};
    }
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

fn tickRed(userdata: ?*anyopaque, ctx: Element.Context) void {
    const self: *Root = @ptrCast(@alignCast(userdata orelse return));

    updateChannel(&self.red, &self.red_dir);
    self.bg = .{ .rgba = .{ self.red, self.green, self.blue, 255 } };
    Element.requestDraw(ctx) catch {};
}

fn tickGreen(userdata: ?*anyopaque, ctx: Element.Context) void {
    const self: *Root = @ptrCast(@alignCast(userdata orelse return));

    updateChannel(&self.green, &self.green_dir);
    self.bg = .{ .rgba = .{ self.red, self.green, self.blue, 255 } };
    Element.requestDraw(ctx) catch {};
}

fn tickBlue(userdata: ?*anyopaque, ctx: Element.Context) void {
    const self: *Root = @ptrCast(@alignCast(userdata orelse return));

    updateChannel(&self.blue, &self.blue_dir);
    self.bg = .{ .rgba = .{ self.red, self.green, self.blue, 255 } };
    Element.requestDraw(ctx) catch {};
}
