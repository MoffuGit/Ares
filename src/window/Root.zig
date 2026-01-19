pub const Root = @This();

const Element = @import("Element.zig");
const Timer = @import("mod.zig").Timer;
const Animation = @import("mod.zig").Animation;
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

pub fn create(alloc: std.mem.Allocator) !*Root {
    const self = try alloc.create(Root);
    self.* = .{
        .element = try Element.init(alloc, .{
            .setupFn = setup,
            .updateFn = update,
            .drawFn = draw,
            .destroyFn = destroy,
        }),
    };
    return self;
}

fn destroy(element: *Element, alloc: std.mem.Allocator) void {
    const self: *Root = @fieldParentPtr("element", element);
    alloc.destroy(self);
}

fn setup(element: *Element, ctx: Element.Context) void {
    const self: *Root = @fieldParentPtr("element", element);

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

    Element.startTimer(ctx, &self.red_timer) catch {};
    Element.startTimer(ctx, &self.green_timer) catch {};
    Element.startTimer(ctx, &self.blue_timer) catch {};
}

fn draw(element: *Element, buffer: *Buffer) void {
    const self: *Root = @fieldParentPtr("element", element);
    buffer.fill(.{ .style = .{ .bg = self.bg } });
}

fn update(element: *Element, time: std.time.Instant) void {
    _ = element;
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
