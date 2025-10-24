const Surface = @This();
const std = @import("std");

const App = @import("App.zig");
const Allocator = std.mem.Allocator;
const Renderer = @import("renderer.zig").Renderer;
const apprt = @import("./apprt/embedded.zig");
const objc = @import("objc");

const log = std.log.scoped(.surface);

alloc: Allocator,

app: *App,

rt_app: *apprt.App,
rt_surface: *apprt.Surface,

renderer: Renderer,

pub fn init(
    self: *Surface,
    alloc: Allocator,
    app: *App,
    rt_app: *apprt.App,
    rt_surface: *apprt.Surface,
) !void {
    const renderer = try Renderer.init(rt_surface);

    self.* = .{
        .renderer = renderer,
        .alloc = alloc,
        .app = app,
        .rt_app = rt_app,
        .rt_surface = rt_surface,
    };
}

pub fn deinit(self: *Surface) void {
    self.renderer.deinit();
    log.info("surface closed addr={x}", .{@intFromPtr(self)});
}
