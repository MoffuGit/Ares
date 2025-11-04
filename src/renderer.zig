pub const Renderer = @This();

const Metal = @import("renderer/Metal.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const Options = @import("renderer/Options.zig");
const ArenaAllocator = std.heap.ArenaAllocator;
const objc = @import("objc");
const mtl = @import("./renderer/metal/api.zig");
const SwapChain = @import("./renderer/SwapChain.zig");
const macos = @import("macos");
const Thread = @import("renderer/Thread.zig");
const xev = @import("global.zig").xev;
const sizepkg = @import("size.zig");

const log = std.log.scoped(.renderer);

pub const GraphicsAPI = Metal;

const shaderpkg = GraphicsAPI.shaders;
const Shaders = shaderpkg.Shaders;
const Buffer = GraphicsAPI.Buffer;

pub const Health = enum(c_int) {
    healthy = 0,
    unhealthy = 1,
};

alloc: Allocator,
size: sizepkg.Size,
api: Metal,
shaders: Shaders,
mutex: std.Thread.Mutex = .{},
health: std.atomic.Value(Health) = .{ .raw = .healthy },
display_link: ?*macos.video.DisplayLink = null,
swap_chain: SwapChain,
first: bool = true,

pub fn init(alloc: Allocator, opts: Options) !Renderer {
    var api = try Metal.init(opts.rt_surface);
    errdefer api.deinit();

    var swap_chain = try SwapChain.init(&api);
    errdefer swap_chain.deinit();

    const display_link = try macos.video.DisplayLink.createWithActiveCGDisplays();
    errdefer display_link.release();

    var renderer = Renderer{ .alloc = alloc, .size = opts.size, .api = api, .shaders = undefined, .swap_chain = swap_chain, .display_link = display_link };

    try renderer.initShaders();

    return renderer;
}

pub fn deinit(self: *Renderer) void {
    self.api.deinit();
    self.swap_chain.deinit();
    if (self.display_link) |link| {
        link.stop() catch {};
        link.release();
    }
    self.deinitShaders();
    self.* = undefined;
}

fn deinitShaders(self: *Renderer) void {
    self.shaders.deinit();
}

fn initShaders(self: *Renderer) !void {
    var shaders = try self.api.initShaders();
    errdefer shaders.deinit(self.alloc);

    self.shaders = shaders;
}

pub fn drawFrame(
    self: *Renderer,
    sync: bool,
) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    self.api.drawFrameStart();
    defer self.api.drawFrameEnd();

    const surface_size = try self.api.surfaceSize();

    if (surface_size.width == 0 or surface_size.height == 0) return;

    const size_changed =
        self.size.screen.width != surface_size.width or
        self.size.screen.height != surface_size.height;

    const needs_redraw =
        size_changed or sync or self.first;

    self.*.first = false;

    if (!needs_redraw) return;

    const frame = try self.swap_chain.nextFrame();
    errdefer self.swap_chain.releaseFrame();

    if (size_changed) {
        self.size.screen = .{
            .width = surface_size.width,
            .height = surface_size.height,
        };
    }

    if (frame.target.width != self.size.screen.width or
        frame.target.height != self.size.screen.height)
    {
        try frame.resize(
            &self.api,
            self.size.screen.width,
            self.size.screen.height,
        );
    }

    var frame_ctx = try self.api.beginFrame(self, &frame.target);
    defer frame_ctx.complete(sync);

    {
        var render_pass = frame_ctx.renderPass(&.{
            .{
                .target = .{
                    .target = frame.target,
                },
                .clear_color = .{ 1.0, 0.0, 0.0, 1.0 },
            },
        });
        defer render_pass.complete();
    }
}

pub fn frameCompleted(
    self: *Renderer,
    health: Health,
) void {
    // If our health value hasn't changed, then we do nothing. We don't
    // do a cmpxchg here because strict atomicity isn't important.
    if (self.health.load(.seq_cst) != health) {
        self.health.store(health, .seq_cst);

        // Our health value changed, so we notify the surface so that it
        // can do something about it.
        // _ = self.surface_mailbox.push(.{
        //     .renderer_health = health,
        // }, .{ .forever = {} });
    }

    // Always release our semaphore
    self.swap_chain.releaseFrame();
}

pub fn hasVsync(self: *const Renderer) bool {
    const display_link = self.display_link orelse return false;
    return display_link.isRunning();
}

pub fn loopEnter(self: *Renderer, thr: *Thread) !void {
    self.api.loopEnter();
    // This is when we know our "self" pointer is stable so we can
    // setup the display link. To setup the display link we set our
    // callback and we can start it immediately.
    const display_link = self.display_link orelse return;
    try display_link.setOutputCallback(
        xev.Async,
        &displayLinkCallback,
        &thr.draw_now,
    );
    display_link.start() catch {};
}

pub fn loopExit(self: *Renderer) void {
    // Stop our display link. If this fails its okay it just means
    // that we either never started it or the view its attached to
    // is gone which is fine.
    const display_link = self.display_link orelse return;
    display_link.stop() catch {};
}

fn displayLinkCallback(
    _: *macos.video.DisplayLink,
    ud: ?*xev.Async,
) void {
    const draw_now = ud orelse return;
    draw_now.notify() catch |err| {
        log.err("error notifying draw_now err={}", .{err});
    };
}
