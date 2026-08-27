const std = @import("std");

const macos = @import("macos");
const objc = @import("objc");

const c = @import("c.zig");

const log = std.log.scoped(.render);
/// Options for initializing a buffer.
pub const Options = struct {
    /// MTLDevice
    device: objc.Object,
    resource_options: c.MTLResourceOptions,
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
        pub fn init(self: *Self, opts: Options, len: usize) !void {
            const buffer = opts.device.msgSend(
                objc.Object,
                objc.sel("newBufferWithLength:options:"),
                .{
                    @as(c_ulong, @intCast(len * @sizeOf(T))),
                    opts.resource_options,
                },
            );

            self.* = .{ .buffer = buffer, .opts = opts, .len = len };
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
        }
    };
}
