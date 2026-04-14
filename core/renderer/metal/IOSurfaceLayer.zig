//! A wrapper around a CALayer with a utility method
//! for settings its `contents` to an IOSurface.
const IOSurfaceLayer = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const objc = @import("objc");
const macos = @import("macos");

const IOSurface = macos.iosurface.IOSurface;

const log = std.log.scoped(.IOSurfaceLayer);

/// The underlying CALayer
layer: objc.Object,

pub fn init(layer: objc.Object) IOSurfaceLayer {
    return .{ .layer = layer };
}

pub fn release(self: *IOSurfaceLayer) void {
    _ = self;
}

/// Sets the layer's `contents` to the provided IOSurface.
///
/// Makes sure to do so on the main thread to avoid visual artifacts.
pub inline fn setSurface(self: *IOSurfaceLayer, surface: *IOSurface) !void {
    // We retain the surface to make sure it's not GC'd
    // before we can set it as the contents of the layer.
    //
    // We release in the callback after setting the contents.
    surface.retain();

    var block = SetSurfaceBlock.init(.{
        .layer = self.layer.value,
        .surface = surface,
    }, &setSurfaceCallback);

    // We check if we're on the main thread and run the block directly if so.
    const NSThread = objc.getClass("NSThread").?;
    if (NSThread.msgSend(bool, "isMainThread", .{})) {
        setSurfaceCallback(&block);
    } else {
        macos.dispatch.dispatch_async(
            @ptrCast(macos.dispatch.queue.getMain()),
            @ptrCast(&block),
        );
    }
}

/// Sets the layer's `contents` to the provided IOSurface.
///
/// Does not ensure this happens on the main thread.
pub inline fn setSurfaceSync(self: *IOSurfaceLayer, surface: *IOSurface) void {
    self.layer.setProperty("contents", surface);
}

const SetSurfaceBlock = objc.Block(struct {
    layer: objc.c.id,
    surface: *IOSurface,
}, .{}, void);

fn setSurfaceCallback(
    block: *const SetSurfaceBlock.Context,
) callconv(.c) void {
    const layer = objc.Object.fromId(block.layer);
    const surface: *IOSurface = block.surface;

    // See explanation of why we retain and release in `setSurface`.
    defer surface.release();

    //BUG:
    // We check to see if the surface is the appropriate size for
    // the layer, if it's not then we discard it. This is because
    // asynchronously drawn frames can sometimes finish just after
    // a synchronously drawn frame during a resize, and if we don't
    // discard the improperly sized surface it creates jank.
    const bounds = layer.getProperty(macos.graphics.Rect, "bounds");
    const scale = layer.getProperty(f64, "contentsScale");
    const width: usize = @intFromFloat(bounds.size.width * scale);
    const height: usize = @intFromFloat(bounds.size.height * scale);
    if (width != surface.getWidth() or height != surface.getHeight()) {
        log.debug(
            "setSurfaceCallback(): surface is wrong size for layer, discarding. surface = {d}x{d}, layer = {d}x{d}",
            .{ surface.getWidth(), surface.getHeight(), width, height },
        );
        return;
    }

    layer.setProperty("contents", surface);
}

pub const LayerCallback = ?*const fn (?*anyopaque) callconv(.c) void;
pub const DisplayCallback = LayerCallback;
pub const ResizeCallback = LayerCallback;

pub fn setDisplayCallback(
    self: *IOSurfaceLayer,
    display_cb: DisplayCallback,
    display_ctx: ?*anyopaque,
) void {
    self.layer.msgSend(void, objc.sel("setDisplayCallback:context:"), .{
        display_cb,
        display_ctx,
    });
}

pub fn setResizeCallback(
    self: *IOSurfaceLayer,
    resize_cb: ResizeCallback,
    resize_ctx: ?*anyopaque,
) void {
    self.layer.msgSend(void, objc.sel("setResizeCallback:context:"), .{
        resize_cb,
        resize_ctx,
    });
}
