const Metal = @import("renderer/Metal.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const size = @import("apprt/embedded.zig").SurfaceSize;
const Options = @import("renderer/Options.zig");
const objc = @import("objc");
const mtl = @import("./renderer/metal/api.zig");

pub const Renderer = struct {
    pub const API = Metal;
    const Target = API.Target;

    alloc: Allocator,
    size: size,
    api: Metal,
    target: Target,

    pub fn init(alloc: Allocator, opts: Options) !Renderer {
        var api = try Metal.init(opts.rt_surface);
        errdefer api.deinit();

        var target = try api.initTarget(800, 600);
        errdefer target.deinit();

        return .{ .alloc = alloc, .size = opts.size, .api = api, .target = target };
    }

    pub fn deinit(self: *Renderer) void {
        self.api.deinit();
        self.target.deinit();
        self.* = undefined;
    }

    pub fn drawFrame(
        self: *Renderer,
        sync: bool,
    ) !void {
        self.api.drawFrameStart();
        defer self.api.drawFrameEnd();

        const surface_size = try self.api.surfaceSize();

        self.size = .{ .height = surface_size.height, .width = surface_size.width };

        var frame_ctx = try self.api.beginFrame(self, &self.target);
        defer frame_ctx.complete(sync);

        var render_pass = frame_ctx.renderPass(&.{
            .{
                .target = .{
                    .target = self.target,
                },
                .clear_color = .{ 0.0, 0.0, 1.0, 1.0 }, // Red color
            },
        });
        render_pass.complete();
    }
};

pub const Health = enum(c_int) {
    healthy = 0,
    unhealthy = 1,
};
