const std = @import("std");
const objc = @import("objc");
const Allocator = std.mem.Allocator;
const constants = @import("contants.zig");
const BUNDLE_ID = constants.BUNDLE_ID;

//Source: https://github.com/ghostty-org/ghostty.git
//LICENSE: [GHOSTTY]

const NSSearchPathDirectory = enum(c_ulong) {
    NSApplicationSupportDirectory = 14,
};

const NSSearchPathDomainMask = enum(c_ulong) {
    NSUserDomainMask = 1,
};

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
