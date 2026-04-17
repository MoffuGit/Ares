pub const Zinio = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.zinio);
const global = @import("global.zig");
const zintect = @import("zintect");
const Buffer = @import("buffer/Buffer.zig");
const xev = global.xev;

pub const Message = struct {
    entry_id: u64,
    version: u64,
    text: []const u8,
    extension: []const u8,
    buffer: *Buffer,

    fn free(self: Message, alloc: Allocator) void {
        alloc.free(self.text);
        alloc.free(self.extension);
    }
};

const Job = struct {
    task: xev.ThreadPool.Task,
    zinio: *Zinio,
    msg: Message,
};

alloc: Allocator,
thread_pool: *xev.ThreadPool,
runtime: zintect.Runtime,
pending: std.atomic.Value(usize) = .{ .raw = 0 },
closing: std.atomic.Value(bool) = .{ .raw = false },

pub fn init(alloc: Allocator, theme_json: []const u8, thread_pool: *xev.ThreadPool) !Zinio {
    var runtime = try zintect.Runtime.init();
    errdefer runtime.deinit();

    _ = runtime.setTheme(theme_json);

    return .{
        .alloc = alloc,
        .thread_pool = thread_pool,
        .runtime = runtime,
    };
}

pub fn deinit(self: *Zinio) void {
    self.closing.store(true, .release);
    while (self.pending.load(.acquire) > 0) {
        std.atomic.spinLoopHint();
    }

    self.runtime.deinit();
}

pub fn schedule(self: *Zinio, msg: Message) void {
    const job = self.alloc.create(Job) catch {
        msg.free(self.alloc);
        return;
    };

    if (self.closing.load(.acquire)) {
        self.alloc.destroy(job);
        msg.free(self.alloc);
        return;
    }

    job.* = .{
        .task = .{ .callback = processJob },
        .zinio = self,
        .msg = msg,
    };

    _ = self.pending.fetchAdd(1, .acq_rel);
    if (self.closing.load(.acquire)) {
        _ = self.pending.fetchSub(1, .acq_rel);
        self.alloc.destroy(job);
        msg.free(self.alloc);
        return;
    }

    self.thread_pool.schedule(xev.ThreadPool.Batch.from(&job.task));
}

fn processJob(task: *xev.ThreadPool.Task) void {
    const job: *Job = @fieldParentPtr("task", task);
    defer job.zinio.finishJob(job);

    job.zinio.processHighlight(job.msg);
}

fn finishJob(self: *Zinio, job: *Job) void {
    job.msg.free(self.alloc);
    self.alloc.destroy(job);
    _ = self.pending.fetchSub(1, .acq_rel);
}

fn processHighlight(self: *Zinio, msg: Message) void {
    var session = zintect.Session.init() catch {
        log.err("failed to create zintect session", .{});
        return;
    };
    defer session.deinit();

    const ext_z = self.alloc.dupeZ(u8, msg.extension) catch return;
    defer self.alloc.free(ext_z);

    if (!session.setSyntaxByExt(&self.runtime, ext_z)) return;

    var lines_list = std.ArrayList([]Buffer.HighlightSpan).initCapacity(msg.buffer.alloc, 0) catch return;
    defer {
        for (lines_list.items) |spans| {
            if (spans.len > 0) msg.buffer.alloc.free(spans);
        }
        lines_list.deinit(msg.buffer.alloc);
    }

    var line_start: usize = 0;
    var line_index: u32 = 0;

    while (true) {
        const line_end = if (std.mem.indexOfScalarPos(u8, msg.text, line_start, '\n')) |pos| pos else msg.text.len;
        const line = msg.text[line_start..line_end];

        const line_z = self.alloc.dupeZ(u8, line) catch return;
        defer self.alloc.free(line_z);

        var collector = Collector{
            .alloc = msg.buffer.alloc,
            .current_line = line,
            .spans = std.ArrayList(Buffer.HighlightSpan).initCapacity(msg.buffer.alloc, 0) catch return,
        };

        _ = session.highlightLine(
            &self.runtime,
            line_z,
            line_index,
            @ptrCast(&collector),
            collectSpan,
        );

        lines_list.append(msg.buffer.alloc, collector.spans.toOwnedSlice(msg.buffer.alloc) catch return) catch return;

        if (line_end >= msg.text.len) break;
        line_start = line_end + 1;
        line_index += 1;
    }

    const result_lines = lines_list.toOwnedSlice(msg.buffer.alloc) catch return;

    var new_highlights = Buffer.Highlights{
        .lines = result_lines,
        .version = msg.version,
    };

    {
        msg.buffer.mutex.lock();
        defer msg.buffer.mutex.unlock();

        if (msg.buffer.text.version != msg.version) {
            new_highlights.deinit(msg.buffer.alloc);
            return;
        }

        msg.buffer.highlights.deinit(msg.buffer.alloc);
        msg.buffer.highlights = new_highlights;
    }

    global.state.emitGlobal(.{ .highlightUpdate = msg.entry_id });
}

const Collector = struct {
    alloc: Allocator,
    current_line: []const u8,
    spans: std.ArrayList(Buffer.HighlightSpan),
};

fn collectSpan(ctx: *anyopaque, _: u32, span: zintect.Span) callconv(.c) void {
    const collector: *Collector = @ptrCast(@alignCast(ctx));

    const start_col = byteToCodepoint(collector.current_line, span.start_byte);
    const end_col = byteToCodepoint(collector.current_line, span.end_byte);

    collector.spans.append(collector.alloc, .{
        .start_col = start_col,
        .end_col = end_col,
        .color = span.color(),
    }) catch return;
}

fn byteToCodepoint(line: []const u8, byte_offset: u32) u32 {
    var cp_count: u32 = 0;
    var i: usize = 0;
    const offset: usize = @min(byte_offset, line.len);

    while (i < offset) {
        const seq_len = std.unicode.utf8ByteSequenceLength(line[i]) catch 1;
        i += @min(seq_len, line.len - i);
        cp_count += 1;
    }

    return cp_count;
}

test "byteToCodepoint maps ASCII byte offsets directly" {
    const line = "pub struct Wow";

    try std.testing.expectEqual(@as(u32, 0), byteToCodepoint(line, 0));
    try std.testing.expectEqual(@as(u32, 1), byteToCodepoint(line, 1));
    try std.testing.expectEqual(@as(u32, 4), byteToCodepoint(line, 4));
    try std.testing.expectEqual(@as(u32, 14), byteToCodepoint(line, 14));
}

test "byteToCodepoint counts multibyte UTF-8 sequences once" {
    const line = "aé🐱z";

    try std.testing.expectEqual(@as(u32, 0), byteToCodepoint(line, 0));
    try std.testing.expectEqual(@as(u32, 1), byteToCodepoint(line, 1));
    try std.testing.expectEqual(@as(u32, 2), byteToCodepoint(line, 3));
    try std.testing.expectEqual(@as(u32, 3), byteToCodepoint(line, 7));
    try std.testing.expectEqual(@as(u32, 4), byteToCodepoint(line, 8));
}
