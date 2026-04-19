const std = @import("std");

pub const c = @cImport(@cInclude("zintect.h"));

pub const Span = extern struct {
    start_byte: u32,
    end_byte: u32,
    r: u8,
    g: u8,
    b: u8,
    a: u8,
    font_style: u8,

    pub fn color(self: Span) [4]u8 {
        return .{ self.r, self.g, self.b, self.a };
    }

    pub fn fontStyle(self: Span) FontStyle {
        return @bitCast(self.font_style);
    }
};

pub const FontStyle = packed struct(u8) {
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,
    _padding: u5 = 0,
};

pub const EmitSpanFn = *const fn (ctx: *anyopaque, line_index: u32, span: Span) callconv(.c) void;

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
        runtime: *const Runtime,
        line: [:0]const u8,
        line_index: u32,
        ctx: *anyopaque,
        emit: EmitSpanFn,
    ) bool {
        return c.zintect_session_highlight_line(
            self.handler,
            runtime.handler,
            line.ptr,
            line_index,
            ctx,
            @ptrCast(emit),
        );
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

    for (lines, 0..) |line, i| {
        _ = session.highlightLine(
            &runtime,
            line,
            @intCast(i),
            @ptrCast(&span_count),
            countSpans,
        );
    }

    try std.testing.expect(span_count > 0);
}

fn countSpans(ctx: *anyopaque, _: u32, _: Span) callconv(.c) void {
    const count: *u32 = @ptrCast(@alignCast(ctx));
    count.* += 1;
}
