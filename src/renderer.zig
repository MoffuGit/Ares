//LICENSE: [GHOSTTY]
//LICENSE: [RADDEBUGGER]

const std = @import("std");
const assert = std.debug.assert;
const Io = std.Io;
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const FrameState = @import("renderer/frame_state.zig");
const SwapChain = FrameState.SwapChain;

const c = @import("c");
const macos = @import("macos");
const objc = @import("objc");

const Metal = @import("renderer/metal.zig");
const win = @import("window.zig");
const Window = win.Window;

const log = std.log.scoped(.render);

pub const Renderer = renderer: {
    if (!builtin.is_test) break :renderer struct {
        api: Metal,

        pub fn init(self: *Renderer) !void {
            self.* = .{
                .api = undefined,
            };

            try self.api.init();
            errdefer self.api.deinit();
        }

        pub fn deinit(self: *Renderer) void {
            self.api.deinit();
        }

        pub fn render(self: *@This(), handle: *Handle, frame_state: *FrameState, sync: bool) void {
            const viewport_size = frame_state.uniform.viewport_size;
            handle.render_handle.update(viewport_size[0], viewport_size[1], sync);

            self.api.start();
            defer self.api.end();

            const render_handle = handle.render_handle;

            var target = render_handle.target();
            var frame = render_handle.frame(self.api, frame_state);
            defer frame.complete(&target, sync);

            var pass = frame.renderPass(&.{
                .{
                    .target = target,
                    .clear_color = .{ 0.0, 0.0, 0.0, 1.0 },
                },
            });
            defer pass.complete();
            //     const arena = state.arena.allocator();
            //     const buffer = arena.rawAlloc(@sizeOf(Rect), .fromByteUnits(heap.pageSize()), @returnAddress()) orelse unreachable;
            //     const input: *Rect = @ptrCast(@alignCast(buffer));
            //
            //     input.* = .{
            //         .position = .{ 10.0, 10.0, 110.0, 110.0 },
            //         .color_0 = .{ 1.0, 0.0, 0.0, 1.0 },
            //         .color_1 = .{ 1.0, 0.0, 0.0, 1.0 },
            //         .color_2 = .{ 1.0, 0.0, 1.0, 1.0 },
            //         .color_3 = .{ 1.0, 0.0, 1.0, 1.0 },
            //     };
            //
            //     const uni_buffer = arena.rawAlloc(@sizeOf(Uniforms), .fromByteUnits(heap.pageSize()), @returnAddress()) orelse unreachable;
            //     const uni_input: *Uniforms = @ptrCast(@alignCast(uni_buffer));
            //
            //     uni_input.* = .{
            //         .viewport_size = .{ @floatFromInt(width), @floatFromInt(height) },
            //     };
            //
            //     var mt_buffer: Buffer = undefined;
            //
            //     try mt_buffer.init(buffer, @sizeOf(Rect), .{ .device = self.api.device, .resource_options = .{
            //         .cpu_cache_mode = .write_combined,
            //         .storage_mode = .shared,
            //     } });
            //
            //     var mt_uni_buffer: Buffer = undefined;
            //
            //     try mt_uni_buffer.init(uni_buffer, @sizeOf(Uniforms), .{ .device = self.api.device, .resource_options = .{
            //         .cpu_cache_mode = .write_combined,
            //         .storage_mode = .shared,
            //     } });
            //
            //     pass.step(.{
            //         .pipeline = self.shaders.pipelines.rect,
            //         .buffers = &.{mt_buffer.buffer},
            //         .uniforms = mt_uni_buffer.buffer,
            //         .draw = .{
            //             .vertex_count = 4,
            //             .type = .triangle_strip,
            //             .instance_count = 1,
            //         },
            //     });
        }

        pub const Handle = struct {
            swap_chain: SwapChain,
            render_handle: Metal.Handle,

            pub fn init(self: *Handle, renderer: *Renderer, window: *Window, gpa: Allocator, io: Io) !void {
                self.* = .{
                    .swap_chain = undefined,
                    .render_handle = undefined,
                };

                try self.swap_chain.init(gpa, io);
                self.render_handle.init(renderer.api, window);
            }

            pub fn deinit(self: *Handle) void {
                self.render_handle.deinit();
                self.swap_chain.deinit();
            }

            pub fn nextFrame(self: *Handle) *FrameState {
                return self.swap_chain.nextFrame();
            }

            pub fn releaseFrame(self: *Handle) void {
                self.swap_chain.releaseFrame();
            }
        };
    };

    break :renderer struct {
        pub const Handle = struct {
            pub fn deinit(_: *@This()) void {}
        };

        pub fn init(_: *Renderer, _: Io) !void {}

        pub fn deinit(_: *Renderer) void {}
    };
};
