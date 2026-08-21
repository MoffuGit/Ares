pub const c = @import("c");

pub const RGFWBool = c.RGFW_bool;
pub const RGFWFalse = c.RGFW_FALSE;
pub const RGFWTrue = c.RGFW_TRUE;

pub const InitFlags = c.RGFW_initFlags;
pub const InitOpenGl = c.RGFW_initOpenGL;
pub const InitEGL = c.RGFW_initEGL;
pub const InitVulkan = c.RGFW_initVulkan;

pub const Window = @import("window.zig");

pub fn init(className: [:0]const u8, flags: InitFlags) !void {
    const status = c.RGFW_init(className, flags);
    if (status != 0) return error.InitError;
}

pub fn deinit() void {
    c.RGFW_deinit();
}

pub fn pollEvents() void {
    c.RGFW_pollEvents();
}
