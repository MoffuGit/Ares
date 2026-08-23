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
const shaders = @import("shaders.zig");
const Shaders = shaders.Shaders;
const RenderPass = @import("render_pass.zig");

//https://developer.apple.com/documentation/coregraphics/cgdirectdisplaycopycurrentmetaldevice(_:)?language=objc
extern "c" fn CGDirectDisplayCopyCurrentMetalDevice(c_uint) ?*anyopaque;

const VertexBuffer = Buffer(shaders.VertexInput);

pub const Renderer = if (builtin.is_test) NoopRenderer else struct {
    layer: objc.Object,
    device: objc.Object,
    queue: objc.Object,
    shaders: Shaders,
    buffer: VertexBuffer,

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

        const sh = try Shaders.init(device, .bgra8unorm, io);

        const buffer = try VertexBuffer.init(.{
            .device = device,
            .resource_options = .{
                // Indicate that the CPU writes to this resource but never reads it.
                .cpu_cache_mode = .write_combined,
                .storage_mode = .managed,
            },
        }, 1);

        self.* = .{
            .buffer = buffer,
            .layer = layer,
            .device = device,
            .queue = queue,
            .shaders = sh,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.queue.release();
        self.shaders.deinit();
        self.buffer.deinit();
    }

    pub fn draw(self: *@This(), window: *Window) void {
        var width: i32, var height: i32 = .{ 0, 0 };
        if (!window.sizeInPixels(&width, &height)) unreachable;

        self.layer.msgSend(void, "drawableSize", .{ width, height });
        const drawable = self.layer.msgSend(objc.Object, "nextDrawable", .{});
        const texture = drawable.msgSend(objc.Object, "texture", .{});

        const buffer = self.queue.msgSend(
            objc.Object,
            objc.sel("commandBuffer"),
            .{},
        );

        const pass = RenderPass.begin(.{
            .command_buffer = buffer,
            .attachments = &.{
                .{
                    .texture = texture,
                    .clear_color = .{ 1.0, 1.0, 1.0, 1.0 },
                },
            },
        });

        const triangle_vertices = [_]shaders.VertexInput{
            .{ .position = .{ 0.0, 0.5, 0.0 }, .color = .{ 1.0, 0.0, 0.0, 1.0 } }, // Top vertex (Red)
            .{ .position = .{ -0.5, -0.5, 0.0 }, .color = .{ 0.0, 1.0, 0.0, 1.0 } }, // Bottom-left vertex (Green)
            .{ .position = .{ 0.5, -0.5, 0.0 }, .color = .{ 0.0, 0.0, 1.0, 1.0 } }, // Bottom-right vertex (Blue)
        };

        self.buffer.sync(&triangle_vertices) catch {};

        pass.step(.{ .pipeline = self.shaders.pipelines.bg_color, .buffers = &.{
            self.buffer.buffer,
        }, .draw = .{
            .vertex_count = 3,
            .type = .triangle,
        } });

        pass.complete();
        buffer.msgSend(void, "presentDrawable:", .{drawable});
        buffer.msgSend(void, objc.sel("commit"), .{});
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

/// Options for initializing a buffer.
pub const Options = struct {
    /// MTLDevice
    device: objc.Object,
    resource_options: mtl.MTLResourceOptions,
};

/// Metal data storage for a certain set of equal types. This is usually
/// used for vertex buffers, etc. This helpful wrapper makes it easy to
/// prealloc, shrink, grow, sync, buffers with Metal.
pub fn Buffer(comptime T: type) type {
    return struct {
        const Self = @This();

        /// The options this buffer was initialized with.
        opts: Options,

        /// The underlying MTLBuffer object.
        buffer: objc.Object,

        /// The allocated length of the buffer.
        /// Note that this is the number
        /// of `T`s not the size in bytes.
        len: usize,

        /// Initialize a buffer with the given length pre-allocated.
        pub fn init(opts: Options, len: usize) !Self {
            const buffer = opts.device.msgSend(
                objc.Object,
                objc.sel("newBufferWithLength:options:"),
                .{
                    @as(c_ulong, @intCast(len * @sizeOf(T))),
                    opts.resource_options,
                },
            );

            return .{ .buffer = buffer, .opts = opts, .len = len };
        }

        /// Init the buffer filled with the given data.
        pub fn initFill(opts: Options, data: []const T) !Self {
            const buffer = opts.device.msgSend(
                objc.Object,
                objc.sel("newBufferWithBytes:length:options:"),
                .{
                    @as(*const anyopaque, @ptrCast(data.ptr)),
                    @as(c_ulong, @intCast(data.len * @sizeOf(T))),
                    opts.resource_options,
                },
            );

            return .{ .buffer = buffer, .opts = opts, .len = data.len };
        }

        pub fn deinit(self: *const Self) void {
            self.buffer.msgSend(void, objc.sel("release"), .{});
        }

        /// Sync new contents to the buffer. The data is expected to be the
        /// complete contents of the buffer. If the amount of data is larger
        /// than the buffer length, the buffer will be reallocated.
        ///
        /// If the amount of data is smaller than the buffer length, the
        /// remaining data in the buffer is left untouched.
        pub fn sync(self: *Self, data: []const T) !void {
            // If we need more bytes than our buffer has, we need to reallocate.
            const req_bytes = data.len * @sizeOf(T);
            const avail_bytes = self.buffer.getProperty(c_ulong, "length");
            if (req_bytes > avail_bytes) {
                // Deallocate previous buffer
                self.buffer.msgSend(void, objc.sel("release"), .{});

                // Allocate a new buffer with enough to hold double what we require.
                self.len = data.len * 2;
                self.buffer = self.opts.device.msgSend(
                    objc.Object,
                    objc.sel("newBufferWithLength:options:"),
                    .{
                        @as(c_ulong, @intCast(self.len * @sizeOf(T))),
                        self.opts.resource_options,
                    },
                );
            }

            // We can fit within the buffer so we can just replace bytes.
            const dst = dst: {
                const ptr = self.buffer.msgSend(?[*]u8, objc.sel("contents"), .{}) orelse {
                    std.log.warn("buffer contents ptr is null", .{});
                    return error.MetalFailed;
                };

                break :dst ptr[0..req_bytes];
            };

            const src = src: {
                const ptr = @as([*]const u8, @ptrCast(data.ptr));
                break :src ptr[0..req_bytes];
            };

            @memcpy(dst, src);

            // If we're using the managed resource storage mode, then
            // we need to signal Metal to synchronize the buffer data.
            //
            // Ref: https://developer.apple.com/documentation/metal/synchronizing-a-managed-resource-in-macos?language=objc
            if (self.opts.resource_options.storage_mode == .managed) {
                self.buffer.msgSend(
                    void,
                    "didModifyRange:",
                    .{macos.foundation.Range.init(0, req_bytes)},
                );
            }
        }

        /// Like Buffer.sync but takes data from an array of ArrayLists,
        /// rather than a single array. Returns the number of items synced.
        pub fn syncFromArrayLists(self: *Self, lists: []const std.ArrayListUnmanaged(T)) !usize {
            var total_len: usize = 0;
            for (lists) |list| {
                total_len += list.items.len;
            }

            // If we need more bytes than our buffer has, we need to reallocate.
            const req_bytes = total_len * @sizeOf(T);
            const avail_bytes = self.buffer.getProperty(c_ulong, "length");
            if (req_bytes > avail_bytes) {
                // Deallocate previous buffer
                self.buffer.msgSend(void, objc.sel("release"), .{});

                // Allocate a new buffer with enough to hold double what we require.
                self.len = total_len * 2;
                self.buffer = self.opts.device.msgSend(
                    objc.Object,
                    objc.sel("newBufferWithLength:options:"),
                    .{
                        @as(c_ulong, @intCast(self.len * @sizeOf(T))),
                        self.opts.resource_options,
                    },
                );
            }

            // We can fit within the buffer so we can just replace bytes.
            const dst = dst: {
                const ptr = self.buffer.msgSend(?[*]u8, objc.sel("contents"), .{}) orelse {
                    std.log.warn("buffer contents ptr is null", .{});
                    return error.MetalFailed;
                };

                break :dst ptr[0..req_bytes];
            };

            var i: usize = 0;

            for (lists) |list| {
                const ptr = @as([*]const u8, @ptrCast(list.items.ptr));
                @memcpy(dst[i..][0 .. list.items.len * @sizeOf(T)], ptr);
                i += list.items.len * @sizeOf(T);
            }

            // If we're using the managed resource storage mode, then
            // we need to signal Metal to synchronize the buffer data.
            //
            // Ref: https://developer.apple.com/documentation/metal/synchronizing-a-managed-resource-in-macos?language=objc
            if (self.opts.resource_options.storage_mode == .managed) {
                self.buffer.msgSend(
                    void,
                    "didModifyRange:",
                    .{macos.foundation.Range.init(0, req_bytes)},
                );
            }

            return total_len;
        }
    };
}
