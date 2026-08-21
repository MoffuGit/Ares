pub const c = @import("c");

pub const RGFWBool = c.RGFW_bool;
pub const RGFWFalse = c.RGFW_FALSE;
pub const RGFWTrue = c.RGFW_TRUE;

pub const InitFlags = c.RGFW_initFlags;
pub const InitOpenGl = c.RGFW_initOpenGL;
pub const InitEGL = c.RGFW_initEGL;
pub const InitVulkan = c.RGFW_initVulkan;

pub const Window = @import("window.zig");

pub fn init(className: [:0]const u8, flags: InitFlags) !void {
    const status = c.RGFW_init(className, flags);
    if (status != 0) return error.InitError;
}

pub fn deinit() void {
    c.RGFW_deinit();
}

pub fn pollEvents() void {
    c.RGFW_pollEvents();
}

pub const Event = c.RGFW_event;

pub const EventNone = c.RGFW_eventNone;
pub const KeyPressed = c.RGFW_keyPressed;
pub const KeyReleased = c.RGFW_keyReleased;
pub const KeyChar = c.RGFW_keyChar;
pub const MouseButtonPressed = c.RGFW_mouseButtonPressed;
pub const MouseButtonReleased = c.RGFW_mouseButtonReleased;
pub const MouseScroll = c.RGFW_mouseScroll;
pub const MouseMotion = c.RGFW_mouseMotion;
pub const MouseRawMotion = c.RGFW_mouseRawMotion;
pub const MouseEnter = c.RGFW_mouseEnter;
pub const MouseLeave = c.RGFW_mouseLeave;
pub const WindowMoved = c.RGFW_windowMoved;
pub const WindowResized = c.RGFW_windowResized;
pub const WindowFocusIn = c.RGFW_windowFocusIn;
pub const WindowFocusOut = c.RGFW_windowFocusOut;
pub const WindowRefresh = c.RGFW_windowRefresh;
pub const WindowClose = c.RGFW_windowClose;
pub const WindowMaximized = c.RGFW_windowMaximized;
pub const WindowMinimized = c.RGFW_windowMinimized;
pub const WindowRestored = c.RGFW_windowRestored;
pub const DataDrop = c.RGFW_dataDrop;
pub const DataDrag = c.RGFW_dataDrag;
pub const ScaleUpdated = c.RGFW_scaleUpdated;
pub const MonitorConnected = c.RGFW_monitorConnected;
pub const MonitorDisconnected = c.RGFW_monitorDisconnected;

pub const MouseLeft = c.RGFW_mouseLeft;
pub const MouseMiddle = c.RGFW_mouseMiddle;
pub const MouseRight = c.RGFW_mouseRight;
pub const MouseMisc1 = c.RGFW_mouseMisc1;
pub const MouseMisc2 = c.RGFW_mouseMisc2;
pub const MouseMisc3 = c.RGFW_mouseMisc3;
pub const MouseMisc4 = c.RGFW_mouseMisc4;
pub const MouseMisc5 = c.RGFW_mouseMisc5;
pub const MouseFinal = c.RGFW_mouseFinal;

pub fn checkEvent(event: *Event) bool {
    return c.RGFW_checkEvent(event) == RGFWTrue;
}
