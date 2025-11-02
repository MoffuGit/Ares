pub const Renderer = @This();

const Metal = @import("renderer/Metal.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const apprt = @import("apprt/embedded.zig");
const Options = @import("renderer/Options.zig");
const ArenaAllocator = std.heap.ArenaAllocator;
const objc = @import("objc");
const mtl = @import("./renderer/metal/api.zig");
const SwapChain = @import("./renderer/SwapChain.zig");

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
size: apprt.SurfaceSize,
api: Metal,
shaders: Shaders,
mutex: std.Thread.Mutex = .{},
health: std.atomic.Value(Health) = .{ .raw = .healthy },
swap_chain: SwapChain,

pub fn init(alloc: Allocator, opts: Options) !Renderer {
    var api = try Metal.init(opts.rt_surface);
    errdefer api.deinit();

    var swap_chain = try SwapChain.init(&api);
    errdefer swap_chain.deinit();

    var renderer = Renderer{ .alloc = alloc, .size = opts.size, .api = api, .shaders = undefined, .swap_chain = swap_chain };

    try renderer.initShaders();

    return renderer;
}

pub fn deinit(self: *Renderer) void {
    self.api.deinit();
    self.swap_chain.deinit();
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
        self.size.width != surface_size.width or
        self.size.height != surface_size.height;

    const needs_redraw =
        size_changed;

    if (!needs_redraw) return;

    const frame = try self.swap_chain.nextFrame();
    errdefer self.swap_chain.releaseFrame();

    if (size_changed) {
        self.size = .{
            .width = surface_size.width,
            .height = surface_size.height,
        };
    }

    if (frame.target.width != self.size.width or
        frame.target.height != self.size.height)
    {
        try frame.resize(
            &self.api,
            self.size.width,
            self.size.height,
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
