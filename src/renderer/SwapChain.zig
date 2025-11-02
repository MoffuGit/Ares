const SwapChain = @This();

const std = @import("std");
const rendererpkg = @import("../renderer.zig");
const GraphicsAPI = rendererpkg.GraphicsAPI;
const FrameState = @import("./FrameState.zig");

// The count of buffers we use for double/triple buffering.
// If this is one then we don't do any double+ buffering at all.
// This is comptime because there isn't a good reason to change
// this at runtime and there is a lot of complexity to support it.
const buf_count = 3;

/// `buf_count` structs that can hold the
/// data needed by the GPU to draw a frame.
frames: [buf_count]FrameState,
/// Index of the most recently used frame state struct.
frame_index: std.math.IntFittingRange(0, buf_count) = 0,
/// Semaphore that we wait on to make sure we have an available
/// frame state struct so we can start working on a new frame.
frame_sema: std.Thread.Semaphore = .{ .permits = buf_count },

/// Set to true when deinited, if you try to deinit a defunct
/// swap chain it will just be ignored, to prevent double-free.
///
/// This is required because of `displayUnrealized`, since it
/// `deinits` the swapchain, which leads to a double-free if
/// the renderer is deinited after that.
defunct: bool = false,

pub fn init(api: *GraphicsAPI) !SwapChain {
    var result: SwapChain = .{ .frames = undefined };

    // Initialize all of our frame state.
    for (&result.frames) |*frame| {
        frame.* = try FrameState.init(api);
    }

    return result;
}

pub fn deinit(self: *SwapChain) void {
    if (self.defunct) return;
    self.defunct = true;

    // Wait for all of our inflight draws to complete
    // so that we can cleanly deinit our GPU state.
    for (0..buf_count) |_| self.frame_sema.wait();
    for (&self.frames) |*frame| frame.deinit();
}

/// Get the next frame state to draw to. This will wait on the
/// semaphore to ensure that the frame is available. This must
/// always be paired with a call to releaseFrame.
pub fn nextFrame(self: *SwapChain) error{Defunct}!*FrameState {
    if (self.defunct) return error.Defunct;

    self.frame_sema.wait();
    errdefer self.frame_sema.post();
    self.frame_index = (self.frame_index + 1) % buf_count;
    return &self.frames[self.frame_index];
}

/// This should be called when the frame g completed drawing.
pub fn releaseFrame(self: *SwapChain) void {
    self.frame_sema.post();
}
