const std = @import("std");
const Allocator = std.mem.Allocator;

pub const c = @cImport(@cInclude("zintect.h"));

pub const FffSpan = extern struct {
    start: u32,
    end: u32,
    color: [4]u8,
    font_style: u8,

    pub fn fontStyle(self: FffSpan) FontStyle {
        return @bitCast(self.font_style);
    }
};

pub const Span = FffSpan;

pub const FontStyle = packed struct(u8) {
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,
    _padding: u5 = 0,
};

pub const HighlightIterator = struct {
    runtime: *const Runtime,
    session: *Session,
    buffer: []u8,
    alloc: Allocator,
    cursor: usize = 0,
    line_index: usize = 0,
    curr: ?[]Span = null,

    pub fn init(
        runtime: *const Runtime,
        session: *Session,
        buffer: []u8,
        alloc: Allocator,
    ) HighlightIterator {
        return .{
            .alloc = alloc,
            .runtime = runtime,
            .session = session,
            .buffer = buffer,
        };
    }

    pub fn deinit(self: *HighlightIterator) void {
        self.freeCurrentResult();
    }

    pub fn next(self: *HighlightIterator) !?[]Span {
        self.freeCurrentResult();

        if (self.cursor >= self.buffer.len) return null;

        const start = self.cursor;
        const line_end = std.mem.indexOfScalarPos(u8, self.buffer, start, '\n') orelse self.buffer.len;
        const end = if (line_end < self.buffer.len) line_end else self.buffer.len;
        const line = self.buffer[start..end];
        self.cursor = if (line_end < self.buffer.len) line_end + 1 else self.buffer.len;
        self.line_index += 1;

        const restore_byte = if (end < self.buffer.len) self.buffer[end] else null;
        if (restore_byte != null) self.buffer[end] = 0;
        defer {
            if (restore_byte) |byte| self.buffer[end] = byte;
        }

        const spans = try self.session.highlightLine(self.alloc, self.runtime, line);
        self.curr = spans;
        return spans;
    }

    fn freeCurrentResult(self: *HighlightIterator) void {
        if (self.curr) |result| {
            self.alloc.free(result);
        }
        self.curr = null;
    }
};

pub const FffResult = extern struct {
    success: bool,
    handle: ?*anyopaque,
};

pub const FffHighlightResult = extern struct {
    items: [*c]FffSpan,
    count: u32,
};

pub const Runtime = struct {
    handler: *anyopaque,

    pub fn init() !Runtime {
        const inst = c.zintect_create_runtime() orelse return error.CreateRuntimeFailed;
        return .{ .handler = inst };
    }

    pub fn deinit(self: *Runtime) void {
        c.zintect_destroy_runtime(self.handler);
    }

    pub fn setTheme(self: *Runtime, theme_json: []const u8) bool {
        return c.zintect_runtime_set_theme(self.handler, theme_json.ptr);
    }
};

pub const Session = struct {
    handler: *anyopaque,

    pub fn init() !Session {
        const inst = c.zintect_create_session() orelse return error.CreateSessionFailed;
        return .{ .handler = inst };
    }

    pub fn deinit(self: *Session) void {
        c.zintect_destroy_session(self.handler);
    }

    pub fn setSyntaxByExt(self: *Session, runtime: *const Runtime, ext: []const u8) bool {
        return c.zintect_session_set_syntax_by_ext(
            self.handler,
            runtime.handler,
            ext.ptr,
        );
    }

    pub fn reset(self: *Session, runtime: *const Runtime) bool {
        return c.zintect_session_reset(self.handler, runtime.handler);
    }

    pub fn highlightIterator(
        self: *Session,
        runtime: *Runtime,
        buffer: []u8,
        alloc: Allocator,
    ) HighlightIterator {
        return HighlightIterator.init(runtime, self, buffer, alloc);
    }

    pub fn highlightLine(
        self: *Session,
        alloc: Allocator,
        runtime: *const Runtime,
        line: []const u8,
    ) ![]FffSpan {
        const null_line = try alloc.dupeZ(u8, line);
        defer alloc.free(null_line);

        const res = c.zintect_session_highlight_line(self.handler, runtime.handler, null_line);
        if (!res.success) return error.HighlightError;

        const handle = res.handle orelse return error.HighlightError;
        const highlight_result: *FffHighlightResult = @ptrCast(@alignCast(handle));
        defer c.fff_free_highlight_result(@ptrCast(highlight_result));

        const count: usize = @intCast(highlight_result.count);
        if (count == 0) return alloc.alloc(FffSpan, 0);
        if (highlight_result.items == null) return error.HighlightError;

        return alloc.dupe(FffSpan, highlight_result.items[0..count]);
    }
};

test "highlight rust source line by line" {
    const alloc = std.testing.allocator;

    var runtime = try Runtime.init();
    defer runtime.deinit();

    var session = try Session.init();
    defer session.deinit();

    try std.testing.expect(session.setSyntaxByExt(&runtime, "rs"));

    const lines = [_][]const u8{
        "pub struct Wow { hi: u64 }\n",
        "fn blah() -> u64 {}\n",
    };

    var span_count: u32 = 0;

    for (lines) |line| {
        const span = try session.highlightLine(alloc, &runtime, line);
        defer alloc.free(span);

        span_count += @intCast(span.len);
    }

    try std.testing.expect(span_count > 0);
}

test "highlightLine accepts raw byte slices" {
    const alloc = std.testing.allocator;

    var runtime = try Runtime.init();
    defer runtime.deinit();

    var session = try Session.init();
    defer session.deinit();

    try std.testing.expect(session.setSyntaxByExt(&runtime, "rs"));

    const raw: [11]u8 = .{ 'l', 'e', 't', ' ', 'x', ' ', '=', ' ', '1', ';', '\n' };
    const spans = try session.highlightLine(alloc, &runtime, raw[0..raw.len]);
    defer alloc.free(spans);

    try std.testing.expect(spans.len > 0);
    try std.testing.expectEqual(@as(u32, 0), spans[0].start);
}

test "highlight iterator walks a raw buffer line by line" {
    const alloc = std.testing.allocator;

    var runtime = try Runtime.init();
    defer runtime.deinit();

    var manual_session = try Session.init();
    defer manual_session.deinit();

    var iter_session = try Session.init();
    defer iter_session.deinit();

    try std.testing.expect(manual_session.setSyntaxByExt(&runtime, "rs"));
    try std.testing.expect(iter_session.setSyntaxByExt(&runtime, "rs"));

    var buffer = [_]u8{
        '/', '*', ' ', 'c', 'o', 'm',  'm', 'e', 'n', 't', '\n',
        's', 't', 'i', 'l', 'l', ' ',  'c', 'o', 'm', 'm', 'e',
        'n', 't', ' ', '*', '/', '\n', 'l', 'e', 't', ' ', 'v',
        'a', 'l', 'u', 'e', ' ', '=',  ' ', '4', '2', ';',
    };

    const expected_lines = [_][]const u8{
        "/* comment",
        "still comment */",
        "let value = 42;",
    };

    var iter = iter_session.highlightIterator(&runtime, &buffer, alloc);
    defer iter.deinit();

    var line_count: usize = 0;
    while (try iter.next()) |spans| {
        defer line_count += 1;

        try std.testing.expect(line_count < expected_lines.len);

        const manual_spans = try manual_session.highlightLine(alloc, &runtime, expected_lines[line_count]);
        defer {
            alloc.free(manual_spans);
        }

        // try std.testing.expectEqual(manual_spans.len, spans.len);
        try std.testing.expectEqualSlices(FffSpan, manual_spans, spans);
    }

    try std.testing.expectEqual(expected_lines.len, line_count);
    try std.testing.expect((try iter.next()) == null);
}
