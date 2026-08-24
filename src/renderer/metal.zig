//LICENSE: [GHOSTTY]

const objc = @import("objc");
const rgfw = @import("rgfw");
const Window = rgfw.Window;

const Renderer = @import("../renderer.zig").Renderer;
const c = @import("metal/c.zig");
const RenderState = Renderer.RenderState;
pub const Pipeline = @import("metal/pipeline.zig");
pub const RenderPass = @import("metal/render_pass.zig");
const shaders = @import("metal/shaders.zig");
pub const Shaders = shaders.Shaders;
pub const VertexInput = shaders.VertexInput;
pub const VertexBuffer = shaders.VertexBuffer;
pub const Target = @import("metal/target.zig");
pub const Frame = @import("metal/frame.zig");

pub const Metal = @This();

pub const Handler = struct {
    layer: objc.Object,

    pub fn setSize(self: *Handler, width: i32, height: i32) void {
        self.layer.msgSend(void, "drawableSize", .{ width, height });
    }

    pub fn init(self: *@This(), api: Metal, window: *Window) void {
        const CAMetalLayer = objc.getClass("CAMetalLayer").?;

        const layer = CAMetalLayer.msgSend(objc.Object, "layer", .{});
        layer.setProperty("device", api.device);
        layer.setProperty("pixelFormat", @intFromEnum(c.MTLPixelFormat.bgra8unorm));

        self.* = .{ .layer = layer };

        const view = objc.Object.fromId(window.NSView() orelse unreachable);
        view.msgSend(void, "setLayer:", .{self.layer});
    }

    pub fn deinit(self: *@This()) void {
        self.layer.release();
    }
};

device: objc.Object,
queue: objc.Object,

autorelease_pool: *objc.AutoreleasePool,

pub fn init(self: *Metal) !void {
    var chosen_device: ?objc.Object = null;

    const devices = objc.Object.fromId(c.MTLCopyAllDevices());

    var iter = devices.iterate();
    while (iter.next()) |device| {
        if (device.getProperty(bool, "isHeadless")) continue;
        chosen_device = device;
        if (device.getProperty(bool, "isRemovable") or
            device.getProperty(bool, "isLowPower")) break;
    }

    const device = chosen_device orelse return error.NoMetalDevice;
    errdefer device.release();

    const queue = device.msgSend(objc.Object, objc.sel("newCommandQueue"), .{});
    errdefer queue.release();

    self.* = .{
        .device = device,
        .queue = queue,
        .autorelease_pool = undefined,
    };
}

pub fn beginFrame(self: *Metal, state: *RenderState, target: *Target) Frame {
    return .begin(self.queue, state, target);
}

pub fn deinit(self: *Metal) void {
    self.device.release();
    self.queue.release();
}
