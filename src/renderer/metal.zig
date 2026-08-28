const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const macos = @import("macos");
const objc = @import("objc");

const win = @import("../window.zig");
const Window = win.Window;
const FrameState = @import("./frame_state.zig");
const c = @import("metal/c.zig");
const Frame = @import("metal/frame.zig");
const Shaders = @import("metal/shaders.zig").Shaders;
const Target = @import("metal/target.zig");
const Buffer = @import("metal/buffer.zig");

pub const Metal = @This();

device: objc.Object,
queue: objc.Object,
shaders: Shaders,

autorelease_pool: ?*objc.AutoreleasePool,

pub fn init(self: *Metal) !void {
    self.* = .{
        .shaders = undefined,
        .device = undefined,
        .queue = undefined,
        .autorelease_pool = null,
    };

    var chosen_device: ?objc.Object = null;

    const devices = objc.Object.fromId(c.MTLCopyAllDevices());

    var iter = devices.iterate();
    while (iter.next()) |device| {
        if (device.getProperty(bool, "isHeadless")) continue;
        chosen_device = device;
        if (device.getProperty(bool, "isRemovable") or
            device.getProperty(bool, "isLowPower")) break;
    }

    self.device = chosen_device orelse return error.NoMetalDevice;
    errdefer self.device.release();

    self.queue = self.device.msgSend(objc.Object, objc.sel("newCommandQueue"), .{});
    errdefer self.queue.release();

    try self.shaders.init(self.device, .bgra8unorm);
}

pub fn buffer(
    self: *Metal,
    chunk: [*]u8,
    len: usize,
    resource_options: c.MTLResourceOptions,
) Buffer {
    return .init(self.device, chunk, len, resource_options);
}

pub fn deinit(self: *Metal) void {
    if (self.autorelease_pool) |pool| pool.deinit();
    self.shaders.deinit();
    self.queue.release();
    self.device.release();
}

pub fn start(self: *Metal) void {
    assert(self.autorelease_pool == null);
    self.autorelease_pool = .init();
}

pub fn end(self: *Metal) void {
    assert(self.autorelease_pool != null);
    self.autorelease_pool.?.deinit();
    self.autorelease_pool = null;
}

pub const Handle = struct {
    layer: objc.Object,

    pub fn init(self: *@This(), api: *Metal, window: *Window) void {
        const CAMetalLayer = objc.getClass("CAMetalLayer").?;

        const layer = CAMetalLayer.msgSend(objc.Object, "layer", .{});
        layer.setProperty("device", api.device);
        layer.setProperty("opaque", true);
        layer.setProperty("pixelFormat", @intFromEnum(c.MTLPixelFormat.bgra8unorm));
        layer.setProperty("contentsGravity", macos.animation.kCAGravityTopLeft);

        const view = objc.Object.fromId(window.NSView() orelse unreachable);
        view.msgSend(void, "setLayer:", .{layer});

        self.* = .{ .layer = layer };
    }

    pub fn frame(
        _: *const @This(),
        api: *Metal,
        frame_state: *FrameState,
    ) Frame {
        return .begin(api, frame_state);
    }

    pub fn target(self: *const Handle) Target {
        return .init(self.layer);
    }

    pub fn deinit(self: *@This()) void {
        self.layer.release();
    }

    pub fn update(self: *@This(), width: f32, height: f32, sync: bool) void {
        const size: macos.graphics.Size = .{
            .width = width,
            .height = height,
        };
        self.layer.msgSend(void, "setDrawableSize:", .{size});

        self.layer.setProperty("presentsWithTransaction", sync);
    }
};
