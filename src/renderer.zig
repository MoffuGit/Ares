const builtin = @import("builtin");
const Io = std.Io;
const Window = @import("window.zig").Window;
const objc = @import("objc");
const std = @import("std");
const assert = std.debug.assert;
const c = @import("c");
const macos = @import("macos");

//https://developer.apple.com/documentation/coregraphics/cgdirectdisplaycopycurrentmetaldevice(_:)?language=objc
extern "c" fn CGDirectDisplayCopyCurrentMetalDevice(c_uint) ?*anyopaque;

/// https://developer.apple.com/documentation/metal/mtlpixelformat?language=objc
pub const MTLPixelFormat = enum(c_ulong) {
    invalid = 0,
    a8unorm = 1,
    r8unorm = 10,
    r8unorm_srgb = 11,
    r8snorm = 12,
    r8uint = 13,
    r8sint = 14,
    r16unorm = 20,
    r16snorm = 22,
    r16uint = 23,
    r16sint = 24,
    r16float = 25,
    rg8unorm = 30,
    rg8unorm_srgb = 31,
    rg8snorm = 32,
    rg8uint = 33,
    rg8sint = 34,
    b5g6r5unorm = 40,
    a1bgr5unorm = 41,
    abgr4unorm = 42,
    bgr5a1unorm = 43,
    r32uint = 53,
    r32sint = 54,
    r32float = 55,
    rg16unorm = 60,
    rg16snorm = 62,
    rg16uint = 63,
    rg16sint = 64,
    rg16float = 65,
    rgba8unorm = 70,
    rgba8unorm_srgb = 71,
    rgba8snorm = 72,
    rgba8uint = 73,
    rgba8sint = 74,
    bgra8unorm = 80,
    bgra8unorm_srgb = 81,
    rgb10a2unorm = 90,
    rgb10a2uint = 91,
    rg11b10float = 92,
    rgb9e5float = 93,
    bgr10a2unorm = 94,
    bgr10_xr = 554,
    bgr10_xr_srgb = 555,
    rg32uint = 103,
    rg32sint = 104,
    rg32float = 105,
    rgba16unorm = 110,
    rgba16snorm = 112,
    rgba16uint = 113,
    rgba16sint = 114,
    rgba16float = 115,
    bgra10_xr = 552,
    bgra10_xr_srgb = 553,
    rgba32uint = 123,
    rgba32sint = 124,
    rgba32float = 125,
    bc1_rgba = 130,
    bc1_rgba_srgb = 131,
    bc2_rgba = 132,
    bc2_rgba_srgb = 133,
    bc3_rgba = 134,
    bc3_rgba_srgb = 135,
    bc4_runorm = 140,
    bc4_rsnorm = 141,
    bc5_rgunorm = 142,
    bc5_rgsnorm = 143,
    bc6h_rgbfloat = 150,
    bc6h_rgbufloat = 151,
    bc7_rgbaunorm = 152,
    bc7_rgbaunorm_srgb = 153,
    pvrtc_rgb_2bpp = 160,
    pvrtc_rgb_2bpp_srgb = 161,
    pvrtc_rgb_4bpp = 162,
    pvrtc_rgb_4bpp_srgb = 163,
    pvrtc_rgba_2bpp = 164,
    pvrtc_rgba_2bpp_srgb = 165,
    pvrtc_rgba_4bpp = 166,
    pvrtc_rgba_4bpp_srgb = 167,
    eac_r11unorm = 170,
    eac_r11snorm = 172,
    eac_rg11unorm = 174,
    eac_rg11snorm = 176,
    eac_rgba8 = 178,
    eac_rgba8_srgb = 179,
    etc2_rgb8 = 180,
    etc2_rgb8_srgb = 181,
    etc2_rgb8a1 = 182,
    etc2_rgb8a1_srgb = 183,
    astc_4x4_srgb = 186,
    astc_5x4_srgb = 187,
    astc_5x5_srgb = 188,
    astc_6x5_srgb = 189,
    astc_6x6_srgb = 190,
    astc_8x5_srgb = 192,
    astc_8x6_srgb = 193,
    astc_8x8_srgb = 194,
    astc_10x5_srgb = 195,
    astc_10x6_srgb = 196,
    astc_10x8_srgb = 197,
    astc_10x10_srgb = 198,
    astc_12x10_srgb = 199,
    astc_12x12_srgb = 200,
    astc_4x4_ldr = 204,
    astc_5x4_ldr = 205,
    astc_5x5_ldr = 206,
    astc_6x5_ldr = 207,
    astc_6x6_ldr = 208,
    astc_8x5_ldr = 210,
    astc_8x6_ldr = 211,
    astc_8x8_ldr = 212,
    astc_10x5_ldr = 213,
    astc_10x6_ldr = 214,
    astc_10x8_ldr = 215,
    astc_10x10_ldr = 216,
    astc_12x10_ldr = 217,
    astc_12x12_ldr = 218,
    astc_4x4_hdr = 222,
    astc_5x4_hdr = 223,
    astc_5x5_hdr = 224,
    astc_6x5_hdr = 225,
    astc_6x6_hdr = 226,
    astc_8x5_hdr = 228,
    astc_8x6_hdr = 229,
    astc_8x8_hdr = 230,
    astc_10x5_hdr = 231,
    astc_10x6_hdr = 232,
    astc_10x8_hdr = 233,
    astc_10x10_hdr = 234,
    astc_12x10_hdr = 235,
    astc_12x12_hdr = 236,
    gbgr422 = 240,
    bgrg422 = 241,
    depth16unorm = 250,
    depth32float = 252,
    stencil8 = 253,
    depth24unorm_stencil8 = 255,
    depth32float_stencil8 = 260,
    x32_stencil8 = 261,
    x24_stencil8 = 262,
};

pub const Renderer = if (builtin.is_test) NoopRenderer else struct {
    device: objc.Object,
    queue: objc.Object,
    library: objc.Object,

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
        layer.setProperty("pixelFormat", @intFromEnum(MTLPixelFormat.bgra8unorm));
        const view = window.NSView() orelse return error.MissingNSView;
        const NSView = objc.Object.fromId(view);
        NSView.msgSend(void, "setLayer:", .{layer});

        const queue = device.msgSend(objc.Object, objc.sel("newCommandQueue"), .{});
        errdefer queue.release();

        const Library = try initLibrary(device, io);

        self.* = .{
            .device = device,
            .queue = queue,
            .library = Library,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.queue.release();
        self.library.release();
    }
};

/// Initialize the MTLLibrary. A MTLLibrary is a collection of shaders.
fn initLibrary(device: objc.Object, io: Io) !objc.Object {
    const start = std.Io.Timestamp.now(io, .real);

    const data = try macos.dispatch.Data.create(
        @embedFile("odyssey_metallib"),
        macos.dispatch.queue.getMain(),
        macos.dispatch.Data.DESTRUCTOR_DEFAULT,
    );
    defer data.release();

    var err: ?*anyopaque = null;
    const library = device.msgSend(
        objc.Object,
        objc.sel("newLibraryWithData:error:"),
        .{
            data,
            &err,
        },
    );
    try checkError(err);

    const end = std.Io.Timestamp.untilNow(start, io, .real);
    std.log.debug("shader library loaded time={}us", .{end.toNanoseconds()});

    return library;
}

pub const NoopRenderer = struct {
    pub fn init(_: *@This(), _: *Window, _: Io) !void {}
    pub fn deinit(_: *@This()) void {}
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
