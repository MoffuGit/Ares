const objc = @import("objc");
const c = @import("metal/c.zig");
pub const Metal = @This();

pub const Pipeline = @import("metal/pipeline.zig");
pub const RenderPass = @import("metal/render_pass.zig");
const shaders = @import("metal/shaders.zig");
pub const Shaders = shaders.Shaders;
pub const VertexInput = shaders.VertexInput;
pub const VertexBuffer = shaders.VertexBuffer;
pub const Target = @import("metal/target.zig");

device: objc.Object,
queue: objc.Object,
layer: objc.Object,

autorelease_pool: *objc.AutoreleasePool,

pub fn init(self: *Metal) !void {
    var chosen_device: ?objc.Object = null;

    const devices = objc.Object.fromId(c.MTLCopyAllDevices());

    var iter = devices.iterate();
    while (iter.next()) |device| {
        // We want a GPU that’s connected to a display.
        if (device.getProperty(bool, "isHeadless")) continue;
        chosen_device = device;
        // If the user has an eGPU plugged in, they probably want
        // to use it. Otherwise, integrated GPUs are better for
        // battery life and thermals.
        if (device.getProperty(bool, "isRemovable") or
            device.getProperty(bool, "isLowPower")) break;
    }

    const device = chosen_device orelse return error.NoMetalDevice;
    errdefer device.release();

    const CAMetalLayer = objc.getClass("CAMetalLayer").?;
    const layer = CAMetalLayer.msgSend(objc.Object, "layer", .{});
    layer.setProperty("device", device);
    layer.setProperty("pixelFormat", @intFromEnum(c.MTLPixelFormat.bgra8unorm));

    const queue = device.msgSend(objc.Object, objc.sel("newCommandQueue"), .{});
    errdefer queue.release();

    self.* = .{
        .layer = layer,
        .device = device,
        .queue = queue,
        .autorelease_pool = undefined,
    };
}

pub fn deinit(self: *Metal) void {
    self.device.release();
    self.queue.release();
    self.layer.release();
}
