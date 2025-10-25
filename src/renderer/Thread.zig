pub const Thread = @This();
const std = @import("std");
const Allocator = std.mem.Allocator;
const apprt = @import("../apprt/embedded.zig");
const rendererpkg = @import("../renderer.zig");
const log = std.log.scoped(.renderer_thread);

alloc: Allocator,

surface: *apprt.Surface,
renderer: *rendererpkg.Renderer,

running: std.atomic.Value(bool),

pub fn init(
    alloc: Allocator,
    surface: *apprt.Surface,
    renderer_impl: *rendererpkg.Renderer,
) !Thread {
    return .{
        .alloc = alloc,
        .surface = surface,
        .renderer = renderer_impl,
        .running = std.atomic.Value(bool).init(true),
    };
}

pub fn threadMain(self: *Thread) void {
    self.threadMain_() catch |err| {
        log.warn("error in renderer err={}", .{err});
    };
}

fn threadMain_(self: *Thread) !void {
    log.debug("starting renderer thread", .{});
    defer log.debug("renderer thread exited", .{});

    const has_loop = @hasDecl(rendererpkg.Renderer, "loopEnter");
    if (has_loop) try self.renderer.api.loopEnter(self);

    while (self.running.load(.seq_cst)) { // Changed: Loop while the `running` flag is true.
        self.drawFrame();
    }
}

fn drawFrame(self: *Thread) void {
    self.renderer.drawFrame(false) catch |err|
        log.warn("error drawing err={}", .{err});
}

pub fn stop(self: *Thread) void {
    self.running.store(false, .seq_cst);
}
