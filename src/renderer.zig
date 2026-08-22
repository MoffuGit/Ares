const builtin = @import("builtin");
const Window = @import("window.zig").Window;
const objc = @import("objc");
const std = @import("std");
const assert = std.debug.assert;

extern "c" fn CGDirectDisplayCopyCurrentMetalDevice(u32) ?*anyopaque;

pub const Renderer = if (builtin.is_test) NoopRenderer else struct {
    device: objc.Object,
    queue: objc.Object,

    pub fn init(self: *@This(), window: *Window) !void {
        const ptr = window.NSWindow() orelse return error.MissingNSWindow;
        const NSWindow = objc.Object.fromId(ptr);
        const NSScreen = NSWindow.getProperty(objc.Object, "screen");

        assert(std.mem.eql(u8, NSScreen.getClassName(), "NSScreen"));

        const descriptor = NSScreen.msgSend(objc.Object, "deviceDescription", .{});
        const NSString = objc.getClass("NSString").?;
        const NSScreenNumber = NSString.msgSend(objc.Object, "stringWithUTF8String:", .{"NSScreenNumber"});

        const screen_number = descriptor.msgSend(objc.Object, "objectForKey:", .{NSScreenNumber});
        const id = screen_number.msgSend(u32, "unsignedIntValue", .{});
        const device = objc.Object.fromId(CGDirectDisplayCopyCurrentMetalDevice(id));

        const queue = device.msgSend(objc.Object, objc.sel("newCommandQueue"), .{});
        errdefer queue.release();

        self.* = .{
            .device = device,
            .queue = queue,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.queue.release();
    }
};

const Device = struct {
    obj: objc.Object,
};

pub const NoopRenderer = struct {
    pub fn init(_: *@This(), _: *Window) !void {}
    pub fn deinit(_: *@This()) void {}
};
