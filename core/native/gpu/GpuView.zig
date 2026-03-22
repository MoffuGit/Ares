const std = @import("std");
const Allocator = std.mem.Allocator;
const GpuContext = @import("metal.zig").GpuContext;
const EditorRenderer = @import("EditorRenderer.zig");
const TerminalRenderer = @import("TerminalRenderer.zig");

const GpuView = @This();

pub const Kind = enum(u8) {
    editor = 0,
    terminal = 1,
};

pub const Renderer = union(Kind) {
    editor: EditorRenderer,
    terminal: TerminalRenderer,
};

alloc: Allocator,
gpu: *GpuContext,
renderer: Renderer,

pub fn create(alloc: Allocator, kind: Kind, layer_ptr: *anyopaque) !*GpuView {
    const gpu = try GpuContext.init(alloc, layer_ptr);
    errdefer gpu.destroy();

    const view = try alloc.create(GpuView);
    errdefer alloc.destroy(view);

    view.* = .{
        .alloc = alloc,
        .gpu = gpu,
        .renderer = switch (kind) {
            .editor => .{ .editor = EditorRenderer.init(gpu) },
            .terminal => .{ .terminal = TerminalRenderer.init(gpu) },
        },
    };

    try gpu.startRenderLoop();

    return view;
}

pub fn resize(self: *GpuView, width: u32, height: u32) void {
    self.gpu.resize(width, height);
}

pub fn destroy(self: *GpuView) void {
    switch (self.renderer) {
        inline else => |*r| r.deinit(),
    }
    self.gpu.destroy();
    self.alloc.destroy(self);
}
