const std = @import("std");

const macos = @import("macos");
const objc = @import("objc");

const c = @import("c.zig");

const log = std.log.scoped(.render);
/// Options for initializing a buffer.
pub const Options = struct {
    resource_options: c.MTLResourceOptions,
};

pub const Buffer = @This();

/// The underlying MTLBuffer object.
buffer: objc.Object,

/// Initialize a buffer with the given length pre-allocated.
pub fn init(
    device: objc.Object,
    chunk: [*]u8,
    len: usize,
    resource_options: c.MTLResourceOptions,
) Buffer {
    const buffer = device.msgSend(
        objc.Object,
        "newBufferWithBytesNoCopy:length:options:deallocator:",
        .{ chunk, @as(c_ulong, @intCast(len)), resource_options },
    );

    return .{ .buffer = buffer };
}

pub fn release(self: *const Buffer) void {
    self.buffer.release();
}
