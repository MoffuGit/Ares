const renderer = @import("../Renderer.zig");
const sizepkg = @import("../size.zig");
const fontpkg = @import("../font/mod.zig");
const objc = @import("objc");
const FrameCallback = @import("../Renderer.zig").FrameCallback;

const MetalLayer = objc.Object;

size: sizepkg.Size,
metal_layer: MetalLayer,
frame_callback: FrameCallback,
state: *anyopaque,

grid: *fontpkg.Grid,
