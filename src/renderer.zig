const Metal = @import("renderer/Metal.zig");

pub const Renderer = Metal;

pub const Health = enum(c_int) {
    healthy = 0,
    unhealthy = 1,
};
