const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = @import("../worktree/io/mod.zig");
const Stat = @import("../worktree/mod.zig").Stat;

pub const Buffer = @This();

pub const State = enum {
    empty,
    loading,
    ready,
    err,
};

entry_id: u64,
state: State = .empty,
file: ?Io.File = null,

pub fn initFromFile(entry_id: u64, file: Io.File) Buffer {
    return .{
        .entry_id = entry_id,
        .state = .ready,
        .file = file,
    };
}

pub fn initLoading(entry_id: u64) Buffer {
    return .{
        .entry_id = entry_id,
        .state = .loading,
    };
}

pub fn deinit(self: *Buffer) void {
    if (self.file) |file| {
        file.deinit();
        self.file = null;
    }
}

pub fn applyFile(self: *Buffer, file: Io.File) void {
    if (self.file) |old| {
        old.deinit();
    }
    self.file = file;
    self.state = .ready;
}

pub fn applyError(self: *Buffer) void {
    if (self.file) |old| {
        old.deinit();
        self.file = null;
    }
    self.state = .err;
}

pub fn bytes(self: *const Buffer) ?[]const u8 {
    if (self.file) |file| return file.bytes;
    return null;
}

pub fn stat(self: *const Buffer) ?Stat {
    if (self.file) |file| return file.stat;
    return null;
}
