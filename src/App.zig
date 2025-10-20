const App = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

alloc: Allocator,

pub fn create(alloc: Allocator) !*App {
    var app = try alloc.create(App);
    errdefer alloc.destroy(app);

    try app.init(alloc);
    return app;
}

pub fn init(self: *App, alloc: Allocator) !void {
    self.* = .{
        .alloc = alloc,
    };
}

pub fn deinit(self: *App) void {
    _ = self;
}

pub fn destroy(self: *App) void {
    self.deinit();

    self.alloc.destroy(self);
}
