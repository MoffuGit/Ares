const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = @import("../io/mod.zig");
const Stat = Io.Stat;
const GapBuffer = @import("datastruct").GapBuffer;

pub const Buffer = @This();

pub const TextBuffer = struct {
    pub const History = struct {};
    pub const Row = struct {
        codepoints: []u32,

        pub fn deinit(self: *Row, alloc: Allocator) void {
            if (self.codepoints.len > 0) {
                alloc.free(self.codepoints);
            }
            self.* = undefined;
        }
    };

    pub const Layout = struct {
        rows: []Row = &.{},

        pub fn deinit(self: *Layout, alloc: Allocator) void {
            for (self.rows) |*row| {
                row.deinit(alloc);
            }
            if (self.rows.len > 0) {
                alloc.free(self.rows);
            }
            self.rows = &.{};
        }

        pub fn rebuild(self: *Layout, alloc: Allocator, content: GapBuffer(u8)) !void {
            self.deinit(alloc);

            var rows = try std.ArrayList(Row).initCapacity(alloc, 0);
            errdefer {
                for (rows.items) |*row| {
                    row.deinit(alloc);
                }
                rows.deinit(alloc);
            }

            var line_bytes = try std.ArrayList(u8).initCapacity(alloc, 0);
            defer line_bytes.deinit(alloc);

            try appendRowsFromBytes(alloc, &rows, &line_bytes, content.items);
            try appendRowsFromBytes(alloc, &rows, &line_bytes, content.secondHalf());
            try appendDecodedRow(alloc, &rows, line_bytes.items);

            self.rows = try rows.toOwnedSlice(alloc);
        }

        pub fn visibleRows(self: *const Layout, scroll_row: u64, max_rows: usize) []const Row {
            const start = @min(std.math.cast(usize, scroll_row) orelse self.rows.len, self.rows.len);
            const count = @min(max_rows, self.rows.len - start);
            return self.rows[start .. start + count];
        }

        fn appendRowsFromBytes(
            alloc: Allocator,
            rows: *std.ArrayList(Row),
            line_bytes: *std.ArrayList(u8),
            raw_bytes: []const u8,
        ) !void {
            var start: usize = 0;
            for (raw_bytes, 0..) |byte, idx| {
                if (byte != '\n') continue;

                try line_bytes.appendSlice(alloc, raw_bytes[start..idx]);
                try appendDecodedRow(alloc, rows, line_bytes.items);
                line_bytes.clearRetainingCapacity();
                start = idx + 1;
            }

            try line_bytes.appendSlice(alloc, raw_bytes[start..]);
        }

        fn appendDecodedRow(
            alloc: Allocator,
            rows: *std.ArrayList(Row),
            row_bytes: []const u8,
        ) !void {
            try rows.append(alloc, .{ .codepoints = try decodeUtf8Line(alloc, row_bytes) });
        }
    };

    alloc: Allocator,
    content: GapBuffer(u8),
    rowCount: usize,
    version: u64,
    layout: Layout = .{},
    history: History = .{},

    pub fn init(alloc: Allocator) TextBuffer {
        return .{
            .alloc = alloc,
            .rowCount = 0,
            .version = 0,
            .content = GapBuffer(u8).init(alloc),
        };
    }

    pub fn initFromBytes(alloc: Allocator, raw: []const u8) !TextBuffer {
        var content = try GapBuffer(u8).initCapacity(alloc, raw.len);
        content.appendSliceBeforeAssumeCapacity(raw);

        var text = TextBuffer.init(alloc);
        text.content = content;
        try text.rebuildDerivedState();
        return text;
    }

    pub fn deinit(self: *TextBuffer) void {
        self.layout.deinit(self.alloc);
        self.content.deinit();
        self.* = undefined;
    }

    pub fn rebuildDerivedState(self: *TextBuffer) !void {
        try self.layout.rebuild(self.alloc, self.content);
        self.rowCount = self.layout.rows.len;
        self.version +%= 1;
    }

    pub fn visibleRows(self: *const TextBuffer, scroll_row: u64, max_rows: usize) []const Row {
        return self.layout.visibleRows(scroll_row, max_rows);
    }

    fn decodeUtf8Line(alloc: Allocator, raw_bytes: []const u8) ![]u32 {
        var codepoints = try std.ArrayList(u32).initCapacity(alloc, 0);
        errdefer codepoints.deinit(alloc);

        const view = std.unicode.Utf8View.initUnchecked(raw_bytes);
        var it = view.iterator();
        while (it.nextCodepoint()) |cp| {
            try codepoints.append(alloc, cp);
        }

        return codepoints.toOwnedSlice(alloc);
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

    const owned_bytes = try self.alloc.dupe(u8, file.bytes);
    self.text = TextBuffer.initFromBytes(self.alloc, owned_bytes) catch |err| {
        self.alloc.free(owned_bytes);
        return err;
    };
    self.file = .{
        .bytes = owned_bytes,
        .stat = file.stat,
        .alloc = self.alloc,
    };
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

test "text buffer caches visible rows and versions derived data" {
    var text = try TextBuffer.initFromBytes(std.testing.allocator, "ab\ncd");
    defer text.deinit();

    try std.testing.expectEqual(@as(usize, 2), text.rowCount);
    try std.testing.expectEqual(@as(u64, 1), text.version);
    try expectAsciiRow(text.visibleRows(0, 2)[0], "ab");
    try expectAsciiRow(text.visibleRows(0, 2)[1], "cd");

    text.content.moveGap(1);
    try text.rebuildDerivedState();

    try std.testing.expectEqual(@as(usize, 2), text.rowCount);
    try std.testing.expectEqual(@as(u64, 2), text.version);
    try expectAsciiRow(text.visibleRows(1, 1)[0], "cd");

    try text.content.insertBefore(text.content.realLength(), '!');
    try text.rebuildDerivedState();

    try std.testing.expectEqual(@as(u64, 3), text.version);
    try expectAsciiRow(text.visibleRows(1, 1)[0], "cd!");
}

fn expectAsciiRow(row: TextBuffer.Row, expected: []const u8) !void {
    try std.testing.expectEqual(expected.len, row.codepoints.len);
    for (expected, 0..) |byte, idx| {
        try std.testing.expectEqual(@as(u32, byte), row.codepoints[idx]);
    }
}
