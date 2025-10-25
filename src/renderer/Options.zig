const apprt = @import("../apprt/embedded.zig");
const renderer = @import("../renderer.zig");

/// The size of everything.
size: apprt.SurfaceSize,
/// The apprt surface.
rt_surface: *apprt.Surface,
