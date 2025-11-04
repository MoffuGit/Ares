const App = @This();

const std = @import("std");
const apprt = @import("apprt/embedded.zig");
const Allocator = std.mem.Allocator;
const SurfaceList = std.ArrayListUnmanaged(*apprt.Surface);
const fontpkg = @import("font/mod.zig");
const Grid = fontpkg.Grid;

alloc: Allocator,
surfaces: SurfaceList,

pub fn create(alloc: Allocator) !*App {
    var app = try alloc.create(App);
    errdefer alloc.destroy(app);

    try app.init(alloc);
    return app;
}

pub fn init(self: *App, alloc: Allocator) !void {
    self.* = .{
        .alloc = alloc,
        .surfaces = .{},
    };
}

pub fn deinit(self: *App) void {
    for (self.surfaces.items) |surface| surface.deinit();
    self.surfaces.deinit(self.alloc);
}

pub fn destroy(self: *App) void {
    self.deinit();

    self.alloc.destroy(self);
}

pub fn addSurface(self: *App, surface: *apprt.Surface) !void {
    try self.surfaces.append(self.alloc, surface);
}

pub fn deleteSurface(self: *App, surface: *apprt.Surface) void {
    var i: usize = 0;
    while (i < self.surfaces.items.len) {
        if (self.surfaces.items[i] == surface) {
            _ = self.surfaces.swapRemove(i);
            continue;
        }

        i += 1;
    }
}
