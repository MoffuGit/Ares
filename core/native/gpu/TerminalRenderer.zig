const std = @import("std");
const GpuContext = @import("metal.zig").GpuContext;

const TerminalRenderer = @This();

gpu: *GpuContext,

pub fn init(gpu: *GpuContext) TerminalRenderer {
    return .{ .gpu = gpu };
}

pub fn render(self: *TerminalRenderer) bool {
    return self.gpu.render();
}

pub fn deinit(self: *TerminalRenderer) void {
    _ = self;
}
