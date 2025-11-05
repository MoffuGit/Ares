const apprt = @import("../apprt/embedded.zig");
const renderer = @import("../renderer.zig");
const sizepkg = @import("../size.zig");
const fontpkg = @import("../font/mod.zig");

/// The size of everything.
size: sizepkg.Size,
/// The apprt surface.
rt_surface: *apprt.Surface,

grid: *fontpkg.Grid,
