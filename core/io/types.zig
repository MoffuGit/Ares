const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Stat = struct {
    size: u64 = 0,
    mtime: i128 = 0,
    atime: i128 = 0,
    ctime: i128 = 0,
    mode: u32 = 0,
};

pub const File = struct {
    bytes: []const u8,
    stat: Stat,
    alloc: Allocator,

    pub fn deinit(self: File) void {
        self.alloc.free(self.bytes);
    }

    pub fn clone(self: File, alloc: Allocator) !File {
        const bytes = try self.alloc.dupe(u8, self.bytes);
        return .{
            .alloc = alloc,
            .stat = self.stat,
            .bytes = bytes,
        };
    }
};

pub const ReadResult = struct {
    path: []const u8,
    file: ?File,
};

pub const WriteResult = struct {
    path: []const u8,
    bytes_written: ?usize,
};
