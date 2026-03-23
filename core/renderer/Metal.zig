const Metal = @This();

const assert = std.debug.assert;
const std = @import("std");
const Allocator = std.mem.Allocator;
const objc = @import("objc");
const macos = @import("macos");
const graphics = macos.graphics;
const Frame = @import("./metal/Frame.zig");
const mtl = @import("./metal/api.zig");

pub const Target = @import("./metal/Target.zig");
pub const shaders = @import("./metal/shaders.zig");
const bufferpkg = @import("metal/buffer.zig");
pub const Buffer = bufferpkg.Buffer;
pub const Texture = @import("metal/Texture.zig");
const fontpkg = @import("../font/mod.zig");

const log = std.log.scoped(.metal);
const Renderer = @import("../Renderer.zig").Renderer;

pub inline fn bufferOptions(self: Metal) bufferpkg.Options {
    return .{
        .device = self.device,
        .resource_options = .{
            // Indicate that the CPU writes to this resource but never reads it.
            .cpu_cache_mode = .write_combined,
            .storage_mode = self.default_storage_mode,
        },
    };
}

pub const uniformBufferOptions = bufferOptions;

/// CAMetalLayer
metal_layer: objc.Object,
/// MTLDevice
device: objc.Object,
/// MTLCommandQueue
queue: objc.Object,

/// The default storage mode to use for resources created with our device.
///
/// This is based on whether the device is a discrete GPU or not, since
/// discrete GPUs do not have unified memory and therefore do not support
/// the "shared" storage mode, instead we have to use the "managed" mode.
default_storage_mode: mtl.MTLResourceOptions.StorageMode,

/// We start an AutoreleasePool before `drawFrame` and end it afterwards.
autorelease_pool: ?*objc.AutoreleasePool = null,

pub fn init(metal_layer: objc.Object) !Metal {
    const device = metal_layer.msgSend(objc.Object, objc.sel("device"), .{});
    if (device.value == null) return error.NoMetalDevice;

    const queue = device.msgSend(objc.Object, objc.sel("newCommandQueue"), .{});
    if (queue.value == null) return error.CommandQueueCreationFailed;

    const default_storage_mode: mtl.MTLResourceOptions.StorageMode =
        if (device.getProperty(bool, "hasUnifiedMemory")) .shared else .managed;

    return .{ .metal_layer = metal_layer, .device = device, .queue = queue, .default_storage_mode = default_storage_mode };
}

pub fn deinit(self: *Metal) void {
    self.queue.release();
}

/// Actions taken before doing anything in `drawFrame`.
///
/// Right now we use this to start an AutoreleasePool.
pub fn drawFrameStart(self: *Metal) void {
    assert(self.autorelease_pool == null);
    self.autorelease_pool = .init();
}

/// Actions taken after `drawFrame` is done.
///
/// Right now we use this to end our AutoreleasePool.
pub fn drawFrameEnd(self: *Metal) void {
    assert(self.autorelease_pool != null);
    self.autorelease_pool.?.deinit();
    self.autorelease_pool = null;
}

/// Begin a frame.
pub inline fn beginFrame(
    self: *const Metal,
    /// Once the frame has been completed, the `frameCompleted` method
    /// on the renderer is called with the health status of the frame.
    renderer: *Renderer,
    /// The target is presented via the provided renderer's API when completed.
    target: *Target,
) !Frame {
    return try Frame.begin(.{ .queue = self.queue }, renderer, target);
}

/// Get the current size of the runtime surface.
pub fn surfaceSize(self: *const Metal) !struct { width: u32, height: u32 } {
    const bounds = self.metal_layer.getProperty(graphics.Rect, "bounds");
    const scale = self.metal_layer.getProperty(f64, "contentsScale");
    return .{
        .width = @intFromFloat(bounds.size.width * scale),
        .height = @intFromFloat(bounds.size.height * scale),
    };
}

pub fn loopEnter(self: *Metal) void {
    _ = self;
}

pub fn initTarget(self: *Metal, width: usize, height: usize) !Target {
    return Target.init(.{ .device = self.device, .pixel_format = .bgra8unorm, .storage_mode = self.default_storage_mode, .width = width, .height = height });
}

pub inline fn present(self: *Metal, target: Target, sync: bool) !void {
    _ = sync;
    self.metal_layer.setProperty("contents", target.surface);
}

pub fn initShaders(
    self: *const Metal,
) !shaders.Shaders {
    return try shaders.Shaders.init(self.device, mtl.MTLPixelFormat.bgra8unorm);
}

pub fn initAtlasTexture(
    self: *const Metal,
    atlas: *const fontpkg.Atlas,
) Texture.Error!Texture {
    const pixel_format: mtl.MTLPixelFormat = switch (atlas.format) {
        .grayscale => .r8unorm,
        .bgra => .bgra8unorm_srgb,
        else => @panic("unsupported atlas format for Metal texture"),
    };

    return try Texture.init(
        .{
            .device = self.device,
            .pixel_format = pixel_format,
            .resource_options = .{
                // Indicate that the CPU writes to this resource but never reads it.
                .cpu_cache_mode = .write_combined,
                .storage_mode = self.default_storage_mode,
            },
            .usage = .{
                // We only need to read from this texture from a shader.
                .shader_read = true,
            },
        },
        atlas.size,
        atlas.size,
        null,
    );
}
