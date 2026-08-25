//LICENSE: [GHOSTTY]

const std = @import("std");
const assert = std.debug.assert;
const Io = std.Io;
const builtin = @import("builtin");

const c = @import("c");
const macos = @import("macos");
const objc = @import("objc");
const win = @import("window.zig");
const Window = win.Window;

const Metal = @import("renderer/metal.zig");
const UniformsBuffer = Metal.UniformsBuffer;
const Uniforms = Metal.Uniforms;
const VertexBuffer = Metal.VertexBuffer;
const VertexInput = Metal.VertexInput;
const Shaders = Metal.Shaders;
const RenderPass = Metal.RenderPass;
const Target = Metal.Target;
const Frame = Metal.Frame;

const log = std.log.scoped(.render);

pub const Renderer = renderer: {
    if (!builtin.is_test) break :renderer struct {
        pub const Handler = Metal.Handler;

        api: Metal,
        shaders: Shaders,

        pub fn init(self: *Renderer, io: Io) !void {
            self.* = .{
                .api = undefined,
                .shaders = undefined,
            };

            try self.api.init(io);
            errdefer self.api.deinit();

            try self.shaders.init(self.api.device, .bgra8unorm, io);
            errdefer self.shaders.deinit();
        }

        pub fn deinit(self: *Renderer) void {
            self.shaders.deinit();
            self.api.deinit();
        }

        pub fn render(self: *@This(), window: *Window, handler: *Handler) !void {
            self.api.start();
            defer self.api.end();

            const width, const height = window.sizeInPixels() orelse return error.MissingWindowSize;

            handler.setSize(width, height);

            var state = handler.frameState();
            var frame = self.api.beginFrame(handler, &state.target);
            var pass = frame.renderPass(&.{
                .{
                    .target = state.target,
                    .clear_color = .{ 1.0, 1.0, 1.0, 1.0 },
                },
            });

            const vertices = [_]VertexInput{
                .{ .position = .{ 10.0, 10.0, 110.0, 110.0 }, .color = .{ 1.0, 0.0, 0.0, 1.0 } },
                .{ .position = .{ 120.0, 120.0, 210.0, 210.0 }, .color = .{ 0.0, 1.0, 0.0, 1.0 } },
                .{ .position = .{ 140.0, 140.0, 240.0, 240.0 }, .color = .{ 0.0, 0.0, 1.0, 1.0 } },
            };

            try state.vertex.sync(&vertices);

            const uniforms = Uniforms{
                .viewport_size = .{ @floatFromInt(width), @floatFromInt(height) },
            };
            try state.uniforms.sync(&.{uniforms});

            pass.step(.{
                .pipeline = self.shaders.pipelines.bg_color,
                .buffers = &.{state.vertex.buffer},
                .uniforms = state.uniforms.buffer,
                .draw = .{
                    .vertex_count = 4,
                    .type = .triangle_strip,
                    .instance_count = vertices.len,
                },
            });

            pass.complete();
            frame.complete();
        }
    };

    break :renderer struct {
        pub const Handler = struct {};

        pub fn init(_: *Renderer, _: Io) !void {}

        pub fn deinit(_: *Renderer) void {}
    };
};
