const Terminal = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Termio = @import("Termio.zig");
const SurfacePkg = @import("Surface.zig");
const sizepkg = @import("size.zig");
const App = @import("App.zig");

const TerminalSurface = SurfacePkg.Surface(Termio);

alloc: Allocator,
surface: *TerminalSurface,

pub fn create(app: *App, alloc: Allocator, layer_ptr: *anyopaque, width: u32, height: u32) !*Terminal {
    const self = try alloc.create(Terminal);
    errdefer alloc.destroy(self);

    const surface = try TerminalSurface.create(alloc, &app.grid, layer_ptr, .{ .width = width, .height = height }, .{});
    errdefer surface.destroy();

    self.* = .{
        .alloc = alloc,
        .surface = surface,
    };

    return self;
}

pub fn resize(self: *Terminal, size: sizepkg.ScreenSize) void {
    self.surface.resize(size);
}

pub fn readSurfaceState(self: *Terminal, out: *@import("global.zig").ExternSurfaceState) void {
    self.surface.readSurfaceState(out);
}

pub fn destroy(self: *Terminal) void {
    self.surface.destroy();
    self.alloc.destroy(self);
}
