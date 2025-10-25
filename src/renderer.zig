const Metal = @import("renderer/Metal.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const size = @import("apprt/embedded.zig").SurfaceSize;
const Options = @import("renderer/Options.zig");
const objc = @import("objc");
const mtl = @import("./renderer/metal/api.zig");

pub const Renderer = struct {
    pub const API = Metal;

    alloc: Allocator,
    size: size,
    api: Metal,

    pub fn init(alloc: Allocator, opts: Options) !Renderer {
        var api = try Metal.init(opts.rt_surface);
        errdefer api.deinit();

        return .{ .alloc = alloc, .size = opts.size, .api = api };
    }

    pub fn deinit(self: *Renderer) void {
        self.api.deinit();
        self.* = undefined;
    }

    pub fn drawFrame(
        self: *Renderer,
        sync: bool,
    ) !void {
        _ = sync;
        // const MTLRenderPassDescriptor = objc.getClass("MTLRenderPassDescriptor").?;
        // const desc = MTLRenderPassDescriptor.msgSend(
        //     objc.Object,
        //     objc.sel("renderPassDescriptor"),
        //     .{},
        // );

        // _ = desc;
        _ = self;

        // const attachments = objc.Object.fromId(
        //     desc.getProperty(?*anyopaque, "colorAttachments"),
        // );
        //
        // attachments.setProperty(
        //     "clearColor",
        //     mtl.MTLClearColor{
        //         .red = 0.0,
        //         .green = 0.0,
        //         .blue = 0.0,
        //         .alpha = 1.0,
        //     },
        // );
        //
        // const buffer = self.api.queue.msgSend(
        //     objc.Object,
        //     objc.sel("commandBuffer"),
        //     .{},
        // );
        //
        // const encoder = buffer.msgSend(
        //     objc.Object,
        //     objc.sel("renderCommandEncoderWithDescriptor:"),
        //     .{desc.value},
        // );
        // encoder.msgSend(void, objc.sel("endEncoding"), .{});
        //
        // buffer.msgSend(void, objc.sel("commit"), .{});
    }
};

pub const Health = enum(c_int) {
    healthy = 0,
    unhealthy = 1,
};
