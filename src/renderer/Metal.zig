const Metal = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const objc = @import("objc");
const macos = @import("macos");
const apprt = @import("../apprt/embedded.zig");
const IOSurfaceLayer = @import("./metal/IOSurfaceLayer.zig");
const mtl = @import("./metal/api.zig");

const log = std.log.scoped(.metal);

layer: IOSurfaceLayer,
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

pub fn init(rt_surface: *apprt.Surface) !Metal {
    // Choose our MTLDevice and create a MTLCommandQueue for that device.
    const device = try chooseDevice();
    errdefer device.release();
    const queue = device.msgSend(objc.Object, objc.sel("newCommandQueue"), .{});
    errdefer queue.release();

    const default_storage_mode: mtl.MTLResourceOptions.StorageMode =
        if (device.getProperty(bool, "hasUnifiedMemory")) .shared else .managed;

    const ViewInfo = struct {
        view: objc.Object,
    };

    const info = ViewInfo{ .view = rt_surface.platform.macos.nsview };

    // Create an IOSurfaceLayer which we can assign to the view to make
    // it in to a "layer-hosting view", so that we can manually control
    // the layer contents.
    var layer = try IOSurfaceLayer.init();
    errdefer layer.release();

    // Add our layer to the view.
    //
    // On macOS we do this by making the view "layer-hosting"
    // by assigning it to the view's `layer` property BEFORE
    // setting `wantsLayer` to `true`.
    //
    // On iOS, views are always layer-backed, and `layer`
    // is readonly, so instead we add it as a sublayer.
    info.view.setProperty("layer", layer.layer.value);
    info.view.setProperty("wantsLayer", true);

    // Ensure that if our layer is oversized it
    // does not overflow the bounds of the view.
    info.view.setProperty("clipsToBounds", true);

    // Ensure that our layer has a content scale set to
    // match the scale factor of the window. This avoids
    // magnification issues leading to blurry rendering.
    // layer.layer.setProperty("contentsScale", info.scaleFactor);

    // This makes it so that our display callback will actually be called.
    layer.layer.setProperty("needsDisplayOnBoundsChange", true);

    return .{ .layer = layer, .device = device, .queue = queue, .default_storage_mode = default_storage_mode };
}

pub fn deinit(self: *Metal) void {
    self.queue.release();
    self.device.release();
    self.layer.release();
}

fn chooseDevice() error{NoMetalDevice}!objc.Object {
    var chosen_device: ?objc.Object = null;

    const devices = objc.Object.fromId(mtl.MTLCopyAllDevices());
    defer devices.release();

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
    return device.retain();
}
