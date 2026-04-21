const std = @import("std");
const Allocator = std.mem.Allocator;

pub const c = @cImport(@cInclude("zintect.h"));

pub const FffSpan = extern struct {
    start_byte: u32,
    end_byte: u32,
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

    pub fn setSyntaxByExt(self: *Session, runtime: *const Runtime, ext: [:0]const u8) bool {
        return c.zintect_session_set_syntax_by_ext(
            self.handler,
            runtime.handler,
            ext.ptr,
        );
    }

    pub fn reset(self: *Session, runtime: *const Runtime) bool {
        return c.zintect_session_reset(self.handler, runtime.handler);
    }

    pub fn highlightLine(
        self: *Session,
        alloc: Allocator,
        runtime: *const Runtime,
        line: [:0]const u8,
    ) ![]FffSpan {
        const res = c.zintect_session_highlight_line(self.handler, runtime.handler, line.ptr);
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
    var runtime = try Runtime.init();
    defer runtime.deinit();

    var session = try Session.init();
    defer session.deinit();

    try std.testing.expect(session.setSyntaxByExt(&runtime, "rs"));

    const lines = [_][:0]const u8{
        "pub struct Wow { hi: u64 }\n",
        "fn blah() -> u64 {}\n",
    };

    var span_count: u32 = 0;

    for (lines) |line| {
        const spans = try session.highlightLine(std.testing.allocator, &runtime, line);
        defer std.testing.allocator.free(spans);
        span_count += @intCast(spans.len);
    }

    try std.testing.expect(span_count > 0);
}
