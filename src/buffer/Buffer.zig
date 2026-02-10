const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = @import("../worktree/io/mod.zig");
const Stat = @import("../worktree/mod.zig").Stat;

const log = std.log.scoped(.buffer);

pub const Buffer = @This();

pub const State = enum {
    empty,
    loading,
    ready,
    err,
};

alloc: Allocator,
entry_id: u64,
io: *Io,
state: State = .empty,
file: ?Io.File = null,

pub fn create(alloc: Allocator, entry_id: u64, io: *Io) !*Buffer {
    const self = try alloc.create(Buffer);
    self.* = .{
        .alloc = alloc,
        .entry_id = entry_id,
        .io = io,
    };
    return self;
}

pub fn destroy(self: *Buffer) void {
    if (self.file) |file| {
        file.deinit();
    }
    self.alloc.destroy(self);
}

pub fn load(self: *Buffer) void {
    self.state = .loading;
    self.io.readFile(self.entry_id, @ptrCast(self), onReadComplete) catch |e| {
        log.err("failed to request read for entry_id={}: {}", .{ self.entry_id, e });
        self.state = .err;
    };
}

fn onReadComplete(userdata: ?*anyopaque, file: ?Io.File) void {
    const self: *Buffer = @ptrCast(@alignCast(userdata));

    if (self.file) |old| {
        old.deinit();
    }

    if (file) |f| {
        self.file = f;
        self.state = .ready;
    } else {
        self.file = null;
        self.state = .err;
        log.err("read failed for entry_id={}", .{self.entry_id});
    }
}

pub fn bytes(self: *const Buffer) ?[]const u8 {
    if (self.file) |file| return file.bytes;
    return null;
}

pub fn stat(self: *const Buffer) ?Stat {
    if (self.file) |file| return file.stat;
    return null;
}
