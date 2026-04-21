const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = @import("io/mod.zig");
const Stat = Io.Stat;
const GapBuffer = @import("datastruct").GapBuffer;
const global = @import("global.zig");
const TextBuffer = @import("Text.zig");

pub const Buffer = @This();

pub const State = enum(u8) {
    empty,
    loading,
    ready,
    err,
};

id: u64,
alloc: Allocator,

state: std.atomic.Value(State) = .{ .raw = .empty },

mutex: std.Thread.Mutex = .{},

file: ?Io.File = null,
text: TextBuffer,
highlights: Highlights = .{},

pub fn init(alloc: Allocator, entry_id: u64) Buffer {
    return .{
        .alloc = alloc,
        .id = entry_id,
        .state = .{ .raw = .loading },
        .text = TextBuffer.init(alloc),
    };
}

pub fn deinit(self: *Buffer) void {
    if (self.file) |f| {
        f.deinit();
    }
    self.text.deinit();
    self.highlights.deinit(self.alloc);
}

pub fn fileUpdate(self: *Buffer, file: ?Io.File) !void {
    defer self.emitUpdate();

    self.mutex.lock();
    defer self.mutex.unlock();

    self.deinit();

    if (file) |f| {
        self.setState(.ready);
        self.file = try f.clone(self.alloc);
        self.text = try TextBuffer.initFromBytes(self.alloc, self.file.?.bytes);
        self.highlights = .{};
    } else {
        self.setState(.err);
    }
}

pub fn emitUpdate(self: *Buffer) void {
    global.state.emitGlobal(.{ .bufferUpdate = self.id });
}

pub fn stat(self: *Buffer) ?Stat {
    self.mutex.lock();
    defer self.mutex.unlock();
    if (self.file) |file| return file.stat;
    return null;
}

pub fn getState(self: *Buffer) State {
    return self.state.load(.acquire);
}

pub fn setState(
    self: *Buffer,
    state: State,
) void {
    self.state.store(state, .release);
}

pub const HighlightSpan = struct {
    start_col: u32,
    end_col: u32,
    color: [4]u8,
    style: @import("font/mod.zig").Style = .regular,
};

pub const Highlights = struct {
    lines: [][]HighlightSpan = &.{},
    version: u64 = 0,

    pub fn deinit(self: *Highlights, alloc: Allocator) void {
        for (self.lines) |line| {
            if (line.len > 0) alloc.free(line);
        }
        if (self.lines.len > 0) alloc.free(self.lines);
        self.* = .{};
    }

    pub fn colorAt(self: *const Highlights, row: usize, col: usize, default: [4]u8) [4]u8 {
        if (row >= self.lines.len) return default;
        for (self.lines[row]) |span| {
            if (col >= span.start_col and col < span.end_col) return span.color;
            if (col < span.start_col) break;
        }
        return default;
    }

    pub fn visibleLines(self: *const Highlights, scroll_row: u64, max_rows: usize) []const []HighlightSpan {
        const start = @min(std.math.cast(usize, scroll_row) orelse self.lines.len, self.lines.len);
        const count = @min(max_rows, self.lines.len - start);
        return self.lines[start .. start + count];
    }
};
