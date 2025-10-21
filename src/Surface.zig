const Surface = @This();
const std = @import("std");

const App = @import("App.zig");
const Allocator = std.mem.Allocator;
const apprt = @import("./apprt/embedded.zig");

const log = std.log.scoped(.surface);

alloc: Allocator,

app: *App,

rt_app: *apprt.App,
rt_surface: *apprt.Surface,

pub fn init(
    self: *Surface,
    alloc: Allocator,
    app: *App,
    rt_app: *apprt.App,
    rt_surface: *apprt.Surface,
) !void {
    self.* = .{
        .alloc = alloc,
        .app = app,
        .rt_app = rt_app,
        .rt_surface = rt_surface,
    };
}

pub fn deinit(self: *Surface) void {
    log.info("surface closed addr={x}", .{@intFromPtr(self)});
}
