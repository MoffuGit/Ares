const std = @import("std");
const vaxis = @import("vaxis");

const Element = @import("element/Element.zig");
const Root = @import("element/Root.zig");
const Buffer = @import("Buffer.zig");
const AppContext = @import("AppContext.zig");

const Allocator = std.mem.Allocator;

const Scene = @This();

alloc: Allocator,

root: *Root,

needs_draw: std.atomic.Value(bool) = std.atomic.Value(bool).init(true),

size: vaxis.Winsize,

pub fn init(alloc: Allocator) !Scene {
    const root = try Root.create(alloc, "root");
    errdefer root.destroy(alloc);

    return .{
        .alloc = alloc,
        .root = root,
        .size = .{ .cols = 0, .rows = 0, .x_pixel = 0, .y_pixel = 0 },
    };
}

pub fn deinit(self: *Scene) void {
    self.root.destroy(self.alloc);
}

pub fn setContext(self: *Scene, ctx: AppContext) void {
    self.root.element.setContext(ctx);
}

pub fn resize(self: *Scene, size: vaxis.Winsize) void {
    if (self.size.rows == size.rows and self.size.cols == size.cols) return;

    self.size = size;
    self.needs_draw.store(true, .release);
}

pub fn needsDraw(self: *Scene) bool {
    return self.needs_draw.load(.acquire);
}

pub fn markDrawn(self: *Scene) void {
    self.needs_draw.store(false, .release);
}

pub fn requestDraw(self: *Scene) void {
    self.needs_draw.store(true, .release);
}

pub fn update(self: *Scene) !void {
    try self.root.element.update();
}

pub fn draw(self: *Scene, buffer: *Buffer) void {
    self.root.element.draw(buffer);
}
