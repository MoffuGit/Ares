const std = @import("std");
const objc = @import("objc");
const Allocator = std.mem.Allocator;

pub const GpuContext = struct {
    alloc: Allocator,
    metal_layer: objc.Object,
    device: objc.Object,
    command_queue: objc.Object,
    width: u32,
    height: u32,
    running: std.atomic.Value(bool),
    render_thread: ?std.Thread,

    pub fn init(alloc: Allocator, layer_ptr: *anyopaque) !*GpuContext {
        const ctx = try alloc.create(GpuContext);
        errdefer alloc.destroy(ctx);

        const metal_layer: objc.Object = .{ .value = @ptrCast(@alignCast(layer_ptr)) };

        const device = metal_layer.msgSend(objc.Object, "device", .{});
        if (device.value == null) return error.NoMetalDevice;

        const command_queue = device.msgSend(objc.Object, "newCommandQueue", .{});
        if (command_queue.value == null) return error.CommandQueueCreationFailed;

        ctx.* = .{
            .alloc = alloc,
            .metal_layer = metal_layer,
            .device = device,
            .command_queue = command_queue,
            .width = 0,
            .height = 0,
            .running = std.atomic.Value(bool).init(false),
            .render_thread = null,
        };

        return ctx;
    }

    pub fn startRenderLoop(self: *GpuContext) !void {
        if (self.running.load(.acquire)) return;
        self.running.store(true, .release);
        self.render_thread = try std.Thread.spawn(.{}, renderLoop, .{self});
    }

    pub fn stopRenderLoop(self: *GpuContext) void {
        if (!self.running.load(.acquire)) return;
        self.running.store(false, .release);
        if (self.render_thread) |thread| {
            thread.join();
            self.render_thread = null;
        }
    }

    fn renderLoop(self: *GpuContext) void {
        while (self.running.load(.acquire)) {
            _ = self.render();
        }
    }

    pub fn render(self: *GpuContext) bool {
        const pool = objc.AutoreleasePool.init();
        defer pool.deinit();

        const drawable = self.metal_layer.msgSend(objc.Object, "nextDrawable", .{});
        if (drawable.value == null) return false;

        const texture = drawable.msgSend(objc.Object, "texture", .{});
        if (texture.value == null) return false;

        const MTLRenderPassDescriptor = objc.getClass("MTLRenderPassDescriptor") orelse return false;
        const desc = MTLRenderPassDescriptor.msgSend(objc.Object, "renderPassDescriptor", .{});
        if (desc.value == null) return false;

        const color_attachments = desc.msgSend(objc.Object, "colorAttachments", .{});
        const attachment0 = color_attachments.msgSend(objc.Object, "objectAtIndexedSubscript:", .{@as(usize, 0)});

        attachment0.msgSend(void, "setTexture:", .{texture});
        attachment0.msgSend(void, "setLoadAction:", .{@as(usize, MTLLoadActionClear)});
        attachment0.msgSend(void, "setStoreAction:", .{@as(usize, MTLStoreActionStore)});
        attachment0.msgSend(void, "setClearColor:", .{MTLClearColor{ .red = 0.0, .green = 0.0, .blue = 0.0, .alpha = 1.0 }});

        const cmd_buf = self.command_queue.msgSend(objc.Object, "commandBuffer", .{});
        if (cmd_buf.value == null) return false;

        const encoder = cmd_buf.msgSend(objc.Object, "renderCommandEncoderWithDescriptor:", .{desc});
        if (encoder.value == null) return false;

        encoder.msgSend(void, "endEncoding", .{});

        cmd_buf.msgSend(void, "presentDrawable:", .{drawable});
        cmd_buf.msgSend(void, "commit", .{});

        return true;
    }

    pub fn resize(self: *GpuContext, width: u32, height: u32) void {
        self.width = width;
        self.height = height;

        const size = CGSize{ .width = @floatFromInt(width), .height = @floatFromInt(height) };
        self.metal_layer.msgSend(void, "setDrawableSize:", .{size});
    }

    pub fn destroy(self: *GpuContext) void {
        self.stopRenderLoop();
        self.command_queue.msgSend(void, "release", .{});
        self.alloc.destroy(self);
    }
};

const MTLLoadActionClear: usize = 2;
const MTLStoreActionStore: usize = 1;

const CGSize = extern struct {
    width: f64,
    height: f64,
};

const MTLClearColor = extern struct {
    red: f64,
    green: f64,
    blue: f64,
    alpha: f64,
};
