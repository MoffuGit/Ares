const renderer = @import("../Renderer.zig");
const sizepkg = @import("../size.zig");
const fontpkg = @import("../font/mod.zig");
const objc = @import("objc");

const MetalLayer = objc.Object;

size: sizepkg.Size,
metal_layer: MetalLayer,

grid: *fontpkg.Grid,
