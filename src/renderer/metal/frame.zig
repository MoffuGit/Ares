//! LICENSE: [GHOSTTY]
//! Wrapper for handling render passes.
const Frame = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const objc = @import("objc");

const c = @import("c.zig");
const Renderer = @import("../../renderer.zig").Renderer;
const RenderState = Renderer.RenderState;
const Metal = @import("../metal.zig");
const Target = @import("target.zig");
const RenderPass = @import("render_pass.zig");

const log = std.log.scoped(.metal);

/// MTLCommandBuffer
buffer: objc.Object,

block: CompletionBlock.Context,

pub fn begin(
    queue: objc.Object,
    render_state: *RenderState,
    target: *Target,
) Frame {
    const buffer = queue.msgSend(
        objc.Object,
        objc.sel("commandBuffer"),
        .{},
    );

    // Create our block to register for completion updates.
    // The block is deallocated by the objC runtime on success.
    const block = CompletionBlock.init(
        .{
            .render_state = render_state,
            .target = target,
        },
        &bufferCompleted,
    );

    return .{ .buffer = buffer, .block = block };
}

/// This is the block type used for the addCompletedHandler callback.
const CompletionBlock = objc.Block(
    struct {
        render_state: *RenderState,
        target: *Target,
    },
    .{},
    void,
);

fn bufferCompleted(
    block: *const CompletionBlock.Context,
) callconv(.c) void {
    block.target.present();
    block.render_state.swap_chain.releaseFrame();
    block.target.deinit();
}

/// Add a render pass to this frame with the provided attachments.
/// Returns a RenderPass which allows render steps to be added.
pub inline fn renderPass(
    self: *const Frame,
    attachments: []const RenderPass.Attachment,
) RenderPass {
    return RenderPass.begin(.{
        .attachments = attachments,
        .command_buffer = self.buffer,
    });
}

pub inline fn complete(self: *Frame) void {
    self.buffer.msgSend(
        void,
        objc.sel("addCompletedHandler:"),
        .{&self.block},
    );

    self.buffer.msgSend(void, objc.sel("commit"), .{});
}
