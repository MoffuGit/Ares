const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = @import("../io/mod.zig");
const Stat = Io.Stat;
const GapBuffer = @import("datastruct").GapBuffer;

pub const Buffer = @This();

pub const TextBuffer = struct {
    pub const History = struct {};

    content: GapBuffer(u8),
    rowCount: usize,
    history: History = .{},

    pub fn init(alloc: Allocator) TextBuffer {
        return .{
            .rowCount = 0,
            .content = GapBuffer(u8).init(alloc),
        };
    }

    pub fn initFromBytes(alloc: Allocator, raw: []const u8) !TextBuffer {
        var content = try GapBuffer(u8).initCapacity(alloc, raw.len);
        content.appendSliceBeforeAssumeCapacity(raw);
        return .{
            .content = content,
            .rowCount = countLines(raw),
        };
    }

    pub fn deinit(self: *TextBuffer) void {
        self.content.deinit();
        self.* = undefined;
    }

    fn countLines(raw: []const u8) usize {
        return std.mem.count(u8, raw, "\n") + 1;
    }
};

pub const State = enum(u8) {
    empty,
    loading,
    ready,
    err,
};

alloc: Allocator,
entry_id: u64,
state: std.atomic.Value(State) = .{ .raw = .empty },
mutex: std.Thread.Mutex = .{},
file: ?Io.File = null,
text: TextBuffer,

pub fn init(alloc: Allocator, entry_id: u64) Buffer {
    return .{
        .alloc = alloc,
        .entry_id = entry_id,
        .state = .{ .raw = .loading },
        .text = TextBuffer.init(alloc),
    };
}

pub fn setFile(self: *Buffer, file: Io.File) !void {
    self.mutex.lock();
    defer self.mutex.unlock();
    self.clearUnlocked();

    self.text = try TextBuffer.initFromBytes(self.alloc, file.bytes);
    self.file = file;
    self.state = .{ .raw = .ready };
}

pub fn deinit(self: *Buffer) void {
    self.mutex.lock();
    defer self.mutex.unlock();
    self.clearUnlocked();
}

pub fn applyFile(self: *Buffer, file: Io.File) void {
    self.setFile(file) catch {
        self.state = .{ .raw = .err };
    };
}

pub fn applyError(self: *Buffer) void {
    self.mutex.lock();
    defer self.mutex.unlock();
    self.clearUnlocked();
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

fn clearUnlocked(self: *Buffer) void {
    self.text.deinit();

    if (self.file) |file| {
        file.deinit();
        self.file = null;
    }
}
