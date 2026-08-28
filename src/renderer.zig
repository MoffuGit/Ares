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
    if (!builtin.is_test) break :renderer Metal;

    break :renderer struct {
        pub fn init(_: *Renderer) !void {}

        pub fn deinit(_: *Renderer) void {}
    };
};

pub const WindowHandle = renderer: {
    if (!builtin.is_test) break :renderer struct {
        swap_chain: SwapChain,
        handle: Renderer.Handle,

        pub fn init(self: *WindowHandle, renderer: *Renderer, window: *Window, gpa: Allocator, io: Io) !void {
            self.* = .{
                .swap_chain = undefined,
                .handle = undefined,
            };

            try self.swap_chain.init(gpa, io);
            self.handle.init(renderer, window);
        }

        pub fn deinit(self: *WindowHandle) void {
            self.handle.deinit();
            self.swap_chain.deinit();
        }

        pub fn nextFrame(self: *WindowHandle) *FrameState {
            return self.swap_chain.nextFrame();
        }

        pub fn releaseFrame(self: *WindowHandle) void {
            self.swap_chain.releaseFrame();
        }
    };

    break :renderer struct {
        pub fn init(_: *WindowHandle, _: *Renderer, _: *Window, _: Allocator, _: Io) !void {}

        pub fn deinit(_: *Renderer) void {}
    };
};

//The sync path i take it from this issue: https://github.com/ocornut/imgui/issues/9500
pub fn render(renderer: *Renderer, window_handle: *WindowHandle, frame_state: *FrameState, sync: bool) void {
    const width, const height = frame_state.uniforms.viewport_size;
    const handle = &window_handle.handle;

    handle.update(width, height, sync);
    var target = handle.target();
    var frame = handle.frame(renderer, frame_state);
    defer frame.complete(&target, sync);

    var pass = frame.renderPass(&.{
        .{
            .target = target,
            .clear_color = .{ 0.0, 0.0, 0.0, 1.0 },
        },
    });
    defer pass.complete();

    // const uniform = renderer.buffer(
    //     @ptrCast(frame_state.uniforms),
    //     @sizeOf(Uniforms),
    //     .{ .storage_mode = .shared, .cpu_cache_mode = .write_combined },
    // );
    //
    // var node: ?*BufferNode = frame_state.rects.nodes.head;
    // while (node) |curr| : (node = curr.next) {
    //     const ptr = curr.pool.ptr;
    //     const instances = curr.pool.reserved;
    //
    //     const rect = renderer.buffer(
    //         @ptrCast(ptr),
    //         @sizeOf(Rect) * instances,
    //         .{ .storage_mode = .shared, .cpu_cache_mode = .write_combined },
    //     );
    //
    //     pass.step(.{
    //         .pipeline = renderer.shaders.pipelines.rect,
    //         .buffers = &.{rect.buffer},
    //         .uniforms = uniform.buffer,
    //         .draw = .{
    //             .vertex_count = 4,
    //             .type = .triangle_strip,
    //             .instance_count = instances,
    //         },
    //     });
    // }
}

test {
    _ = FrameState;
}
