const c = @import("c");
const root = @import("root.zig");

pub const Flags = c.RGFW_windowFlags;
pub const WindowNoBorder = c.RGFW_windowNoBorder;
pub const WindowNoResize = c.RGFW_windowNoResize;
pub const WindowAllowDND = c.RGFW_windowAllowDND;
pub const WindowHideMouse = c.RGFW_windowHideMouse;
pub const WindowFullScreen = c.RGFW_windowFullscreen;
pub const WindowTranslucent = c.RGFW_windowTranslucent;
pub const WindowCenter = c.RGFW_windowCenter;
pub const WindowRawMouse = c.RGFW_windowRawMouse;
pub const WindowScaleToMonitor = c.RGFW_windowScaleToMonitor;
pub const WindowHide = c.RGFW_windowHide;
pub const WindowMaximize = c.RGFW_windowMaximize;
pub const WindowCenterCurosr = c.RGFW_windowCenterCursor;
pub const WindowFloating = c.RGFW_windowFloating;
pub const WindowFocusOnShow = c.RGFW_windowFocusOnShow;
pub const WindowMinimize = c.RGFW_windowMinimize;
pub const WindowFocus = c.RGFW_windowFocus;
pub const WindowCaptureMouse = c.RGFW_windowCaptureMouse;
pub const WindowOpenGL = c.RGFW_windowOpenGL;
pub const WindowEGL = c.RGFW_windowEGL;

pub const Window = @This();

handle: *c.struct_RGFW_window,

pub fn init(self: *Window, name: [:0]const u8, x: i32, y: i32, w: i32, h: i32, flags: Flags) !void {
    const handle = c.RGFW_createWindow(name, x, y, w, h, flags) orelse return error.CreateWindowError;

    self.* = .{
        .handle = handle,
    };
}

pub fn shouldClose(self: *Window) bool {
    return c.RGFW_window_shouldClose(self.handle) == root.RGFWTrue;
}

pub fn deinit(self: *Window) void {
    c.RGFW_window_close(self.handle);
}
