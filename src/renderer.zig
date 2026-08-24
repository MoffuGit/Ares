const std = @import("std");
const assert = std.debug.assert;
const Io = std.Io;
const builtin = @import("builtin");

const c = @import("c");
const macos = @import("macos");
const objc = @import("objc");

const Metal = @import("renderer/metal.zig");
const VertexBuffer = Metal.VertexBuffer;
const Shaders = Metal.Shaders;
const RenderPass = Metal.RenderPass;
const Window = @import("window.zig").Window;

const log = std.log.scoped(.render);

pub const Renderer = renderer: {
    if (!builtin.is_test) break :renderer struct {
        api: Metal,
        shaders: Shaders,

        buffer: VertexBuffer,

        pub fn init(self: *Renderer, window: *Window, io: Io) !void {
            self.* = .{
                .api = undefined,
                .buffer = undefined,
                .shaders = undefined,
            };

            try self.api.init();
            errdefer self.api.deinit();

            const view = window.NSView() orelse unreachable;
            const NSView = objc.Object.fromId(view);
            NSView.msgSend(void, "setLayer:", .{self.api.layer});

            try self.shaders.init(self.api.device, .bgra8unorm, io);
            errdefer self.shaders.deinit();

            try self.buffer.init(.{
                .device = self.api.device,
                .resource_options = .{
                    .cpu_cache_mode = .write_combined,
                    .storage_mode = .managed,
                },
            }, 1);

            errdefer self.buffer.deinit();
        }

        pub fn deinit(self: *Renderer) void {
            self.shaders.deinit();
            self.buffer.deinit();
            self.api.deinit();
        }

        //     pub fn draw(self: *@This(), window: *Window) void {
        //         var width: i32, var height: i32 = .{ 0, 0 };
        //         if (!window.sizeInPixels(&width, &height)) unreachable;
        //
        //         self.layer.msgSend(void, "drawableSize", .{ width, height });
        //         const drawable = self.layer.msgSend(objc.Object, "nextDrawable", .{});
        //         const texture = drawable.msgSend(objc.Object, "texture", .{});
        //
        //         const buffer = self.queue.msgSend(
        //             objc.Object,
        //             objc.sel("commandBuffer"),
        //             .{},
        //         );
        //
        //         const pass = RenderPass.begin(.{
        //             .command_buffer = buffer,
        //             .attachments = &.{
        //                 .{
        //                     .texture = texture,
        //                     .clear_color = .{ 1.0, 1.0, 1.0, 1.0 },
        //                 },
        //             },
        //         });
        //
        //         const triangle_vertices = [_]shaders.VertexInput{
        //             .{ .position = .{ 0.0, 0.5, 0.0 }, .color = .{ 1.0, 0.0, 0.0, 1.0 } }, // Top vertex (Red)
        //             .{ .position = .{ -0.5, -0.5, 0.0 }, .color = .{ 0.0, 1.0, 0.0, 1.0 } }, // Bottom-left vertex (Green)
        //             .{ .position = .{ 0.5, -0.5, 0.0 }, .color = .{ 0.0, 0.0, 1.0, 1.0 } }, // Bottom-right vertex (Blue)
        //         };
        //
        //         self.buffer.sync(&triangle_vertices) catch {};
        //
        //         pass.step(.{ .pipeline = self.shaders.pipelines.bg_color, .buffers = &.{
        //             self.buffer.buffer,
        //         }, .draw = .{
        //             .vertex_count = 3,
        //             .type = .triangle,
        //         } });
        //
        //         pass.complete();
        //         buffer.msgSend(void, "presentDrawable:", .{drawable});
        //         buffer.msgSend(void, objc.sel("commit"), .{});
        //     }

    };

    break :renderer struct {
        pub fn init(_: *Renderer, _: *Window, _: Io) !void {}

        pub fn deinit(_: *Renderer) void {}
    };
};
