//! LICENSE: [GHOSTTY]
//! Wrapper for handling render passes.

const std = @import("std");
const Allocator = std.mem.Allocator;

const objc = @import("objc");

const Handle = @import("../metal.zig").Handle;
const Metal = @import("../metal.zig");
const c = @import("c.zig");
const RenderPass = @import("render_pass.zig");
const Target = @import("target.zig");

const Frame = @This();

const log = std.log.scoped(.metal);

/// MTLCommandBuffer
buffer: objc.Object,

block: CompletionBlock.Context,

pub fn begin(
    handler: *Handle,
    api: Metal,
) Frame {
    const buffer = api.queue.msgSend(
        objc.Object,
        objc.sel("commandBuffer"),
        .{},
    );

    // Create our block to register for completion updates.
    // The block is deallocated by the objC runtime on success.
    const block = CompletionBlock.init(
        .{ .handler = handler },
        &bufferCompleted,
    );

    return .{ .buffer = buffer, .block = block };
}

/// This is the block type used for the addCompletedHandler callback.
const CompletionBlock = objc.Block(
    struct { handler: *Handle },
    .{},
    void,
);

fn bufferCompleted(
    block: *const CompletionBlock.Context,
) callconv(.c) void {
    block.handler.swap_chain.releaseFrame();
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

pub inline fn complete(self: *Frame, target: *Target, sync: bool) void {
    if (!sync) {
        self.buffer.msgSend(
            void,
            objc.sel("addCompletedHandler:"),
            .{&self.block},
        );

        self.buffer.msgSend(void, "presentDrawable:", .{target.drawable});
    }

    self.buffer.msgSend(void, "commit", .{});

    if (sync) {
        self.buffer.msgSend(void, "waitUntilCompleted", .{});
        CompletionBlock.invoke(&self.block, .{});
        target.drawable.msgSend(void, "present", .{});
    }
}
