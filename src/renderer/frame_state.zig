const std = @import("std");
const Allocator = std.mem.Allocator;
const heap = std.heap;

const datastruct = @import("../datastruct.zig");

pub const SwapChain = datastruct.SwapChain(FrameState, 3);

pub const FrameState = @This();

swap_chain: *SwapChain,
arena: heap.ArenaAllocator,
uniform: Uniforms,

pub fn init(self: *FrameState, swap_chain: *SwapChain, gpa: Allocator) !void {
    self.* = .{
        .uniform = undefined,
        .swap_chain = swap_chain,
        .arena = .init(gpa),
    };
}

pub fn deinit(self: *FrameState) void {
    self.arena.deinit();
}

pub fn release(self: *FrameState) void {
    _ = self.arena.reset(.free_all);
    self.swap_chain.releaseFrame();
}

pub const Uniforms = extern struct {
    viewport_size: [2]f32 align(8),
};

pub const Rect = extern struct {
    position: [4]f32 align(16),
    color_0: [4]f32 align(16),
    color_1: [4]f32 align(16),
    color_2: [4]f32 align(16),
    color_3: [4]f32 align(16),
};
