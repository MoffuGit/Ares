const std = @import("std");
const GpuContext = @import("metal.zig").GpuContext;

const EditorRenderer = @This();

gpu: *GpuContext,

pub fn init(gpu: *GpuContext) EditorRenderer {
    return .{ .gpu = gpu };
}

pub fn render(self: *EditorRenderer) bool {
    return self.gpu.render();
}

pub fn deinit(self: *EditorRenderer) void {
    _ = self;
}
