//LICENSE: [GHOSTTY]

const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;

const macos = @import("macos");
const objc = @import("objc");

const win = @import("../window.zig");
const Window = win.Window;
const c = @import("metal/c.zig");
pub const Frame = @import("metal/frame.zig");
pub const Pipeline = @import("metal/pipeline.zig");
pub const RenderPass = @import("metal/render_pass.zig");
const shaders = @import("metal/shaders.zig");
pub const Shaders = shaders.Shaders;
pub const VertexInput = shaders.VertexInput;
pub const VertexBuffer = shaders.VertexBuffer;
pub const UniformsBuffer = shaders.UniformsBuffer;
pub const Uniforms = shaders.Uniforms;
pub const Target = @import("metal/target.zig");

pub const Metal = @This();

io: Io,

device: objc.Object,
queue: objc.Object,

autorelease_pool: ?*objc.AutoreleasePool,

pub fn init(self: *Metal, io: Io) !void {
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
        .io = io,
        .device = device,
        .queue = queue,
        .autorelease_pool = null,
    };
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

pub fn deinit(self: *Metal) void {
    self.device.release();
    self.queue.release();
}

pub const Handle = struct {
    io: Io,
    layer: objc.Object,
    swap_chain: SwapChain,

    pub fn init(self: *@This(), api: Metal, window: *Window) !void {
        const CAMetalLayer = objc.getClass("CAMetalLayer").?;

        const layer = CAMetalLayer.msgSend(objc.Object, "layer", .{});
        layer.setProperty("device", api.device);
        layer.setProperty("opaque", true);
        layer.setProperty("pixelFormat", @intFromEnum(c.MTLPixelFormat.bgra8unorm));
        layer.setProperty("contentsGravity", macos.animation.kCAGravityTopLeft);

        self.* = .{ .layer = layer, .swap_chain = undefined, .io = api.io };

        const view = objc.Object.fromId(window.NSView() orelse unreachable);
        view.msgSend(void, "setLayer:", .{self.layer});

        try self.swap_chain.init(api);
    }

    pub fn frameState(self: *Handle) *FrameState {
        return self.swap_chain.nextFrame(self.io);
    }

    pub fn releaseFrame(self: *Handle) void {
        self.swap_chain.releaseFrame(self.io);
    }

    pub fn frame(self: *Handle, api: Metal) Frame {
        return .begin(self, api);
    }

    pub fn target(self: *Handle) Target {
        return .init(self.layer);
    }

    pub fn deinit(self: *@This()) void {
        self.layer.release();
        self.swap_chain.deinit(self.io);
    }

    pub fn setSize(self: *Handle, width: i32, height: i32) void {
        const size: macos.graphics.Size = .{
            .width = @floatFromInt(width),
            .height = @floatFromInt(height),
        };
        self.layer.msgSend(void, "setDrawableSize:", .{size});
    }
};

const SwapChain = struct {
    const buf_count = 3;

    frames: [buf_count]FrameState,
    frame_index: std.math.IntFittingRange(0, buf_count) = 0,
    frame_sema: std.Io.Semaphore = .{ .permits = buf_count },

    pub fn init(self: *SwapChain, api: Metal) !void {
        self.* = .{
            .frames = undefined,
        };

        for (&self.frames) |*frame| {
            try frame.init(api);
        }
    }

    pub fn deinit(self: *SwapChain, io: Io) void {
        for (0..buf_count) |_| self.frame_sema.waitUncancelable(io);
        for (&self.frames) |*frame| frame.deinit();
    }

    pub fn nextFrame(self: *SwapChain, io: Io) *FrameState {
        self.frame_sema.waitUncancelable(io);
        errdefer self.frame_sema.post();
        self.frame_index = (self.frame_index + 1) % buf_count;
        return &self.frames[self.frame_index];
    }

    pub fn releaseFrame(self: *SwapChain, io: Io) void {
        self.frame_sema.post(io);
    }
};

const FrameState = struct {
    vertex: VertexBuffer,
    uniforms: UniformsBuffer,

    pub fn init(self: *FrameState, api: Metal) !void {
        self.* = .{
            .uniforms = undefined,
            .vertex = undefined,
        };

        try self.vertex.init(.{
            .device = api.device,
            .resource_options = .{
                .cpu_cache_mode = .write_combined,
                .storage_mode = .shared,
            },
        }, 1);

        try self.uniforms.init(.{
            .device = api.device,
            .resource_options = .{
                .cpu_cache_mode = .write_combined,
                .storage_mode = .shared,
            },
        }, 1);
    }

    pub fn deinit(self: *FrameState) void {
        self.vertex.deinit();
        self.uniforms.deinit();
    }
};
