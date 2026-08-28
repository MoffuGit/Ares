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

pub const Buffer = @This();

/// The underlying MTLBuffer object.
buffer: objc.Object,

/// Initialize a buffer with the given length pre-allocated.
pub fn init(self: *@This(), chunk: [*]u8, len: usize, opts: Options) !void {
    self.* = .{ .buffer = undefined };

    self.buffer = opts.device.msgSend(
        objc.Object,
        "newBufferWithBytesNoCopy:length:options:deallocator:",
        .{ chunk, @as(c_ulong, @intCast(len)), opts.resource_options },
    );
}
