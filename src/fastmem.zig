const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;

/// Same as @memcpy but prefers libc memcpy if it is available
/// because it is generally much faster.
pub inline fn copy(comptime T: type, dest: []T, source: []const T) void {
    if (builtin.link_libc) {
        _ = memcpy(dest.ptr, source.ptr, source.len * @sizeOf(T));
    } else {
        @memcpy(dest[0..source.len], source);
    }
}

extern "c" fn memcpy(*anyopaque, *const anyopaque, usize) *anyopaque;
