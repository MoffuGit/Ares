//LICENSE: [GHOSTTY]
//LICENSE: [RADDEBUGGER]

const std = @import("std");
const assert = std.debug.assert;
const Io = std.Io;
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const FrameState = @import("renderer/frame_state.zig");
const SwapChain = FrameState.SwapChain;
const BufferNode = FrameState.BufferNode;
const Buffer = Metal.Buffer;
const Rect = FrameState.Rect;
const Uniforms = FrameState.Uniforms;

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

        //The sync path i take it from this issue: https://github.com/ocornut/imgui/issues/9500
        pub fn render(self: *@This(), handle: *Handle, frame_state: *FrameState, sync: bool) void {
            const viewport_size = frame_state.uniforms.viewport_size;
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

            const uniform = self.api.buffer(
                @ptrCast(frame_state.uniforms),
                @sizeOf(Uniforms),
                .{ .storage_mode = .shared, .cpu_cache_mode = .write_combined },
            );

            var node: ?*BufferNode = frame_state.rect_list.nodes.head;
            while (node) |curr| : (node = curr.next) {
                const ptr = curr.pool.buffer.ptr;
                const instances = curr.pool.reserved;

                const rect = self.api.buffer(
                    @ptrCast(ptr),
                    @sizeOf(Rect) * instances,
                    .{ .storage_mode = .shared, .cpu_cache_mode = .write_combined },
                );

                pass.step(.{
                    .pipeline = self.api.shaders.pipelines.rect,
                    .buffers = &.{rect.buffer},
                    .uniforms = uniform.buffer,
                    .draw = .{
                        .vertex_count = 4,
                        .type = .triangle_strip,
                        .instance_count = instances,
                    },
                });
            }
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

        pub fn init(_: *Renderer) !void {}

        pub fn deinit(_: *Renderer) void {}
    };
};

test {
    _ = FrameState;
}
