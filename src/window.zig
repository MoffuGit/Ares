const std = @import("std");
const Io = std.Io;
const builtin = @import("builtin");

const c = @import("c");
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

pub const Window = window: {
    if (!builtin.is_test) break :window struct {
        win: *c.struct_RGFW_window,

        pub fn init(
            self: *@This(),
            name: [:0]const u8,
            x: i32,
            y: i32,
            width: i32,
            height: i32,
            flags: Flags,
        ) !void {
            self.* = .{
                .win = undefined,
            };

            self.win = c.RGFW_createWindow(
                name,
                x,
                y,
                width,
                height,
                flags,
            ) orelse return error.RGFWCreation;
        }

        pub fn deinit(self: *@This()) void {
            c.RGFW_window_close(self.win);
        }

        pub fn shouldClose(self: *@This()) bool {
            return c.RGFW_window_shouldClose(self.win) == c.RGFW_TRUE;
        }

        pub fn NSWindow(self: *@This()) ?*anyopaque {
            return c.RGFW_window_getWindow_OSX(self.win);
        }

        pub fn NSView(self: *@This()) ?*anyopaque {
            return c.RGFW_window_getView_OSX(self.win);
        }

        pub fn sizeInPixels(self: *@This()) ?struct { i32, i32 } {
            var width: i32, var height: i32 = .{ 0, 0 };

            if (c.RGFW_window_getSizeInPixels(self.win, &width, &height) == c.RGFW_TRUE) {
                return .{ width, height };
            }

            return null;
        }
    };

    break :window struct {
        pub fn init(
            _: *@This(),
            _: [:0]const u8,
            _: i32,
            _: i32,
            _: i32,
            _: i32,
            _: Flags,
        ) !void {}

        pub fn deinit(self: *@This()) void {
            _ = self;
        }
    };
};
