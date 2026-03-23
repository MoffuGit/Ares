const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = @import("../io/mod.zig");
const Stat = Io.Stat;

pub const Buffer = @This();

pub const State = enum(u8) {
    empty,
    loading,
    ready,
    err,
};

entry_id: u64,
state: std.atomic.Value(State) = .{ .raw = .empty },
mutex: std.Thread.Mutex = .{},
file: ?Io.File = null,

pub fn initFromFile(entry_id: u64, file: Io.File) Buffer {
    return .{
        .entry_id = entry_id,
        .state = .{ .raw = .ready },
        .file = file,
    };
}

pub fn initLoading(entry_id: u64) Buffer {
    return .{
        .entry_id = entry_id,
        .state = .{ .raw = .loading },
    };
}

pub fn deinit(self: *Buffer) void {
    self.mutex.lock();
    defer self.mutex.unlock();
    if (self.file) |file| {
        file.deinit();
        self.file = null;
    }
}

pub fn applyFile(self: *Buffer, file: Io.File) void {
    self.mutex.lock();
    defer self.mutex.unlock();
    if (self.file) |old| {
        old.deinit();
    }
    self.file = file;
    self.state.store(.ready, .release);
}

pub fn applyError(self: *Buffer) void {
    self.mutex.lock();
    defer self.mutex.unlock();
    if (self.file) |old| {
        old.deinit();
        self.file = null;
    }
    self.state.store(.err, .release);
}

pub fn bytes(self: *Buffer) ?[]const u8 {
    self.mutex.lock();
    defer self.mutex.unlock();
    if (self.file) |file| return file.bytes;
    return null;
}

pub fn stat(self: *Buffer) ?Stat {
    self.mutex.lock();
    defer self.mutex.unlock();
    if (self.file) |file| return file.stat;
    return null;
}

pub fn getState(self: *const Buffer) State {
    return self.state.load(.acquire);
}
