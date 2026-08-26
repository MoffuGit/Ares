//LICENSE: [GHOSTTY]
//LICENSE: [RADDEBUGGER]

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
        pub const Handle = Metal.Handle;

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

        pub fn render(self: *@This(), window: *Window, handler: *Handle) !void {
            self.api.start();
            defer self.api.end();

            const width, const height = window.sizeInPixels() orelse return error.MissingWindowSize;

            handler.setSize(width, height);

            var state = handler.frameState();

            const vertices = [_]VertexInput{
                .{
                    .position = .{ 10.0, 10.0, 110.0, 110.0 },
                    .color_0 = .{ 1.0, 0.0, 0.0, 1.0 },
                    .color_1 = .{ 1.0, 0.0, 0.0, 1.0 },
                    .color_2 = .{ 1.0, 0.0, 1.0, 1.0 },
                    .color_3 = .{ 1.0, 0.0, 1.0, 1.0 },
                },
            };

            try state.vertex.sync(&vertices);

            const uniforms = Uniforms{
                .viewport_size = .{ @floatFromInt(width), @floatFromInt(height) },
            };

            try state.uniforms.sync(&.{uniforms});

            var frame = handler.frame(self);
            defer frame.complete();

            var target = handler.target();
            defer target.complete(&frame);

            var pass = frame.renderPass(&.{
                .{
                    .target = target,
                    .clear_color = .{ 1.0, 0.0, 0.0, 1.0 },
                },
            });
            defer pass.complete();

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
        }
    };

    break :renderer struct {
        pub const Handle = struct {
            pub fn deinit(_: *@This()) void {}
        };

        pub fn init(_: *Renderer, _: Io) !void {}

        pub fn deinit(_: *Renderer) void {}
    };
};
