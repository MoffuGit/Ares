const builtin = @import("builtin");
const Io = std.Io;
const Window = @import("window.zig").Window;
const objc = @import("objc");
const std = @import("std");
const assert = std.debug.assert;
const c = @import("c");
const macos = @import("macos");
const mtl = @import("api.zig");
const Pipeline = @import("pipeline.zig");
const Shaders = @import("shaders.zig").Shaders;

//https://developer.apple.com/documentation/coregraphics/cgdirectdisplaycopycurrentmetaldevice(_:)?language=objc
extern "c" fn CGDirectDisplayCopyCurrentMetalDevice(c_uint) ?*anyopaque;

pub const Renderer = if (builtin.is_test) NoopRenderer else struct {
    device: objc.Object,
    queue: objc.Object,
    shaders: Shaders,

    pub fn init(self: *@This(), window: *Window, io: Io) !void {
        const win = window.NSWindow() orelse return error.MissingNSWindow;
        const NSWindow = objc.Object.fromId(win);
        const NSScreen = NSWindow.getProperty(objc.Object, "screen");

        assert(std.mem.eql(u8, NSScreen.getClassName(), "NSScreen"));

        const descriptor = NSScreen.msgSend(objc.Object, "deviceDescription", .{});
        const NSString = objc.getClass("NSString").?;
        const NSScreenNumber = NSString.msgSend(objc.Object, "stringWithUTF8String:", .{"NSScreenNumber"});

        const screen_number = descriptor.msgSend(objc.Object, "objectForKey:", .{NSScreenNumber});
        const id = screen_number.msgSend(u32, "unsignedIntValue", .{});
        const device = objc.Object.fromId(CGDirectDisplayCopyCurrentMetalDevice(id));

        const CAMetalLayer = objc.getClass("CAMetalLayer").?;
        const layer = CAMetalLayer.msgSend(objc.Object, "layer", .{});
        layer.setProperty("device", device);
        layer.setProperty("pixelFormat", @intFromEnum(mtl.MTLPixelFormat.bgra8unorm));
        const view = window.NSView() orelse return error.MissingNSView;
        const NSView = objc.Object.fromId(view);
        NSView.msgSend(void, "setLayer:", .{layer});

        const queue = device.msgSend(objc.Object, objc.sel("newCommandQueue"), .{});
        errdefer queue.release();

        const shaders = try Shaders.init(device, .bgra8unorm, io);

        self.* = .{
            .device = device,
            .queue = queue,
            .shaders = shaders,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.queue.release();
        self.shaders.deinit();
    }

    pub fn draw(self: *@This()) void {
        _ = self;
    }
};

pub const NoopRenderer = struct {
    pub fn init(_: *@This(), _: *Window, _: Io) !void {}
    pub fn deinit(_: *@This()) void {}
    pub fn draw(_: *@This()) void {}
};

fn checkError(err_: ?*anyopaque) !void {
    const nserr = objc.Object.fromId(err_ orelse return);
    const str = @as(
        *macos.foundation.String,
        @ptrCast(nserr.getProperty(?*anyopaque, "localizedDescription").?),
    );

    std.log.err("metal error={s}", .{str.cstringPtr(.ascii).?});
    return error.MetalFailed;
}
