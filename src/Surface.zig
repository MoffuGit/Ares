const Surface = @This();
const std = @import("std");

const App = @import("App.zig");
const Allocator = std.mem.Allocator;
const Renderer = @import("renderer.zig").Renderer;
const apprt = @import("./apprt/embedded.zig");
const objc = @import("objc");

const rendererpkg = @import("./renderer/Thread.zig"); // Added: Import the renderer_thread module.

const log = std.log.scoped(.surface);

alloc: Allocator,

app: *App,

rt_app: *apprt.App,
rt_surface: *apprt.Surface,

size: apprt.SurfaceSize,

renderer: Renderer,
renderer_thread: rendererpkg.Thread,
renderer_thr: std.Thread,

pub fn init(
    self: *Surface,
    alloc: Allocator,
    app: *App,
    rt_app: *apprt.App,
    rt_surface: *apprt.Surface,
) !void {
    const renderer = try Renderer.init(alloc, .{ .size = rt_surface.size, .rt_surface = rt_surface });

    const size = rt_surface.size;

    const renderer_thread = try rendererpkg.Thread.init(alloc, rt_surface, &self.renderer);

    self.* = .{ .renderer = renderer, .alloc = alloc, .app = app, .rt_app = rt_app, .rt_surface = rt_surface, .size = size, .renderer_thread = renderer_thread, .renderer_thr = undefined };

    self.renderer_thr = try std.Thread.spawn(.{}, rendererpkg.Thread.threadMain, .{&self.renderer_thread});
}

pub fn deinit(self: *Surface) void {
    self.renderer.deinit();
    self.renderer_thread.stop();
    std.Thread.join(self.renderer_thr);
    log.info("surface closed addr={x}", .{@intFromPtr(self)});
}

pub fn updateSize(self: *Surface, size: apprt.SurfaceSize) void {
    if (self.size == size) return;

    self.size = size;
}
