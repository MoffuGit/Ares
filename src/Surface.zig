const Surface = @This();
const std = @import("std");

const App = @import("App.zig");
const Allocator = std.mem.Allocator;
const apprt = @import("./apprt/embedded.zig");
const objc = @import("objc");

const log = std.log.scoped(.surface);

alloc: Allocator,

app: *App,

rt_app: *apprt.App,
rt_surface: *apprt.Surface,

render_thread: ?std.Thread,
render_count: usize,
running: bool,

fn renderLoop(surface_ptr: *Surface) void {
    var self = surface_ptr;
    while (self.running) {
        self.render_count += 1;
        log.info("Render count: {d}", .{self.render_count});
        std.Thread.sleep(std.time.ns_per_s);
    }
    log.info("Render thread stopped for surface addr={x}", .{@intFromPtr(self)});
}

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
        .render_thread = null,
        .render_count = 0,
        .running = true,
    };

    self.render_thread = try std.Thread.spawn(.{}, renderLoop, .{self});
}

pub fn deinit(self: *Surface) void {
    log.info("surface closed addr={x}", .{@intFromPtr(self)});

    self.running = false;

    if (self.render_thread) |thread_id| {
        thread_id.join();
        log.info("Render thread joined for surface addr={x}", .{@intFromPtr(self)});
    }
}
