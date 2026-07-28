const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");

const objc = @import("objc");

const constants = @import("constants.zig");
const BUNDLE_ID = constants.BUNDLE_ID;

const log = std.log.scoped(.os);
//Source: https://github.com/ghostty-org/ghostty.git
//LICENSE: [GHOSTTY]

const NSSearchPathDirectory = enum(c_ulong) {
    NSApplicationSupportDirectory = 14,
};

const NSSearchPathDomainMask = enum(c_ulong) {
    NSUserDomainMask = 1,
};

pub fn raiseFdLimit() void {
    if (builtin.os.tag != .macos) return;

    const posix = std.posix;
    var lim = posix.getrlimit(.NOFILE) catch return;
    if (lim.cur >= lim.max) return;

    var min: posix.rlim_t = lim.cur;
    var max: posix.rlim_t = 1 << 20;
    if (lim.max != posix.RLIM.INFINITY) {
        min = lim.max;
        max = lim.max;
    }

    while (true) {
        lim.cur = min + @divTrunc(max - min, 2);
        if (posix.setrlimit(.NOFILE, lim)) |_| {
            min = lim.cur;
        } else |_| {
            max = lim.cur;
        }
        if (min + 1 >= max) break;
    }
    log.debug("file handle limit raised value={}", .{lim.cur});
}

pub fn appSupportPath(alloc: std.mem.Allocator, sub_path: []const u8) ![]const u8 {
    return try commonDir(
        alloc,
        .NSApplicationSupportDirectory,
        &.{ BUNDLE_ID, sub_path },
    );
}

fn commonDir(
    alloc: std.mem.Allocator,
    directory: NSSearchPathDirectory,
    sub_paths: []const []const u8,
) ![]const u8 {
    const NSFileManager = objc.getClass("NSFileManager").?;
    const manager = NSFileManager.msgSend(objc.Object, objc.sel("defaultManager"), .{});

    const url = manager.msgSend(objc.Object, objc.sel("URLForDirectory:inDomain:appropriateForURL:create:error:"), .{
        directory,
        NSSearchPathDomainMask.NSUserDomainMask,
        @as(?*anyopaque, null),
        true,
        @as(?*anyopaque, null),
    });

    if (url.value == null) return error.AppleAPIFailed;

    const path = url.getProperty(objc.Object, "path");
    const c_str = path.getProperty(?[*:0]const u8, "UTF8String") orelse return error.AppleAPIFailed;
    const base_dir = std.mem.sliceTo(c_str, 0);

    var paths = try alloc.alloc([]const u8, sub_paths.len + 1);
    defer alloc.free(paths);

    paths[0] = base_dir;
    @memcpy(paths[1..], sub_paths);

    return try std.fs.path.join(alloc, paths);
}
