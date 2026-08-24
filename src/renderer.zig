//LICENSE: [GHOSTTY]

const std = @import("std");
const assert = std.debug.assert;
const Io = std.Io;
const builtin = @import("builtin");

const c = @import("c");
const macos = @import("macos");
const objc = @import("objc");
const rgfw = @import("rgfw");
const Window = rgfw.Window;

const Metal = @import("renderer/metal.zig");
const VertexBuffer = Metal.VertexBuffer;
const VertexInput = Metal.VertexInput;
const Shaders = Metal.Shaders;
const RenderPass = Metal.RenderPass;
const Handler = Metal.Handler;
const Target = Metal.Target;
const Frame = Metal.Frame;

const log = std.log.scoped(.render);

pub const Renderer = renderer: {
    if (!builtin.is_test) break :renderer struct {
        api: Metal,
        shaders: Shaders,

        pub fn init(self: *Renderer, io: Io) !void {
            self.* = .{
                .api = undefined,
                .shaders = undefined,
            };

            try self.api.init();
            errdefer self.api.deinit();

            try self.shaders.init(self.api.device, .bgra8unorm, io);
            errdefer self.shaders.deinit();
        }

        pub fn deinit(self: *Renderer) void {
            self.shaders.deinit();
            self.api.deinit();
        }

        pub fn render(self: *@This(), window: *Window, state: *RenderState) !void {
            self.api.start();
            defer self.api.end();

            var width: i32, var height: i32 = .{ 0, 0 };
            assert(window.sizeInPixels(&width, &height));

            state.handler.setSize(width, height);

            var frame_state = state.swap_chain.nextFrame();
            frame_state.target.init(state.handler);

            var frame = self.api.beginFrame(state, &frame_state.target);
            var pass = frame.renderPass(&.{
                .{
                    .target = frame_state.target,
                    .clear_color = .{ 1.0, 1.0, 1.0, 1.0 },
                },
            });

            const triangle_vertices = [_]VertexInput{
                .{ .position = .{ 0.0, 0.5, 0.0 }, .color = .{ 1.0, 0.0, 0.0, 1.0 } }, // Top vertex (Red)
                .{ .position = .{ -0.5, -0.5, 0.0 }, .color = .{ 0.0, 1.0, 0.0, 1.0 } }, // Bottom-left vertex (Green)
                .{ .position = .{ 0.5, -0.5, 0.0 }, .color = .{ 0.0, 0.0, 1.0, 1.0 } }, // Bottom-right vertex (Blue)
            };

            try frame_state.buffer.sync(&triangle_vertices);

            pass.step(.{ .pipeline = self.shaders.pipelines.bg_color, .buffers = &.{
                frame_state.buffer.buffer,
            }, .draw = .{
                .vertex_count = 3,
                .type = .triangle,
            } });

            pass.complete();
            frame.complete();
        }

        const SwapChain = struct {
            const buf_count = 3;

            io: Io,
            frames: [buf_count]FrameState,
            frame_index: std.math.IntFittingRange(0, buf_count) = 0,
            frame_sema: std.Io.Semaphore = .{ .permits = buf_count },

            pub fn init(self: *SwapChain, api: Metal, io: Io) !void {
                self.* = .{
                    .io = io,
                    .frames = undefined,
                };

                for (&self.frames) |*frame| {
                    try frame.init(api);
                }
            }

            pub fn deinit(self: *SwapChain) void {
                for (0..buf_count) |_| self.frame_sema.waitUncancelable(self.io);
                for (&self.frames) |*frame| frame.deinit();
            }

            pub fn nextFrame(self: *SwapChain) *FrameState {
                self.frame_sema.waitUncancelable(self.io);
                errdefer self.frame_sema.post();
                self.frame_index = (self.frame_index + 1) % buf_count;
                return &self.frames[self.frame_index];
            }

            pub fn releaseFrame(self: *SwapChain) void {
                self.frame_sema.post(self.io);
            }

            const FrameState = struct {
                buffer: VertexBuffer,
                target: Target = undefined,

                pub fn init(self: *FrameState, api: Metal) !void {
                    self.* = .{
                        .buffer = undefined,
                        .target = undefined,
                    };

                    try self.buffer.init(.{
                        .device = api.device,
                        .resource_options = .{
                            .cpu_cache_mode = .write_combined,
                            .storage_mode = .managed,
                        },
                    }, 1);
                }

                pub fn deinit(self: *FrameState) void {
                    self.buffer.deinit();
                }
            };
        };

        pub const RenderState = struct {
            handler: Handler,
            swap_chain: SwapChain,

            pub fn init(self: *@This(), renderer: *Renderer, window: *Window, io: Io) !void {
                self.* = .{
                    .handler = undefined,
                    .swap_chain = undefined,
                };

                self.handler.init(renderer.api, window);
                try self.swap_chain.init(renderer.api, io);
            }

            pub fn deinit(self: *@This()) void {
                self.handler.deinit();
                self.swap_chain.deinit();
            }
        };
    };

    break :renderer struct {
        pub fn init(_: *Renderer, _: Io) !void {}

        pub fn deinit(_: *Renderer) void {}
    };
};
