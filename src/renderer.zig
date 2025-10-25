const Metal = @import("renderer/Metal.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const size = @import("apprt/embedded.zig").SurfaceSize;
const Options = @import("renderer/Options.zig");

pub const Renderer = struct {
    pub const API = Metal;

    alloc: Allocator,
    size: size,
    api: Metal,

    pub fn init(alloc: Allocator, opts: Options) !Renderer {
        var api = try Metal.init(opts.rt_surface);
        errdefer api.deinit();

        return .{ .alloc = alloc, .size = opts.size, .api = api };
    }

    pub fn deinit(self: *Renderer) void {
        self.api.deinit();
        self.* = undefined;
    }

    pub fn drawFrame(
        self: *Renderer,
        sync: bool,
    ) !void {
        _ = self;
        _ = sync;
    }
};

pub const Health = enum(c_int) {
    healthy = 0,
    unhealthy = 1,
};
