const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = @import("io/mod.zig");
const Stat = Io.Stat;
const global = @import("global.zig");
const TextBuffer = @import("Text.zig");
const ThreadPool = global.xev.ThreadPool;
const Style = @import("font/mod.zig").Style;
const zintect = @import("zintect");

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

rwlock: std.Thread.RwLock = .{},

file: ?Io.File = null,
text: TextBuffer,
extension: ?[]u8,

highlights: Highlights = .{},

runtime: zintect.Runtime,
pool: *ThreadPool,

stopped: std.atomic.Value(bool) = .{ .raw = false },
active: std.atomic.Value(bool) = .{ .raw = false },

task: ThreadPool.Task = .{
    .callback = highlightTask,
},

pub const Options = struct {
    extension: ?[]u8 = null,
    id: u64,
    runtime: zintect.Runtime,
    pool: *ThreadPool,
};

pub fn init(alloc: Allocator, opts: Options) !Buffer {
    return .{
        .alloc = alloc,
        .id = opts.id,
        .state = .{ .raw = .loading },
        .text = TextBuffer.init(alloc),
        .pool = opts.pool,
        .runtime = opts.runtime,
        .extension = opts.extension,
    };
}

pub fn deinit(self: *Buffer) void {
    self.stopped.store(true, .release);

    while (self.active.load(.acquire)) {
        std.atomic.spinLoopHint();
    }

    if (self.file) |f| {
        f.deinit();
    }
    self.text.deinit();
    self.highlights.deinit(self.alloc);
    if (self.extension) |ext| {
        self.alloc.free(ext);
    }
}

pub fn insertUtf8At(self: *Buffer, row: usize, col: usize, bytes: []const u8) !void {
    {
        self.rwlock.lock();
        defer self.rwlock.unlock();

        try self.text.insertUtf8At(row, col, bytes);
    }

    self.requestHighlight();
    self.emitUpdate();
}

pub fn deleteAt(self: *Buffer, row: usize, col: usize) !bool {
    const changed = blk: {
        self.rwlock.lock();
        defer self.rwlock.unlock();

        break :blk try self.text.deleteAt(row, col);
    };

    if (changed) {
        self.requestHighlight();
        self.emitUpdate();
    }
    return changed;
}

pub fn backspaceAt(self: *Buffer, row: usize, col: usize) !bool {
    const changed = blk: {
        self.rwlock.lock();
        defer self.rwlock.unlock();

        break :blk try self.text.backspaceAt(row, col);
    };

    if (changed) {
        self.requestHighlight();
        self.emitUpdate();
    }
    return changed;
}

pub fn getColsCountAt(self: *Buffer, row: usize) usize {
    self.rwlock.lock();
    defer self.rwlock.unlock();

    return self.text.layout.rows[row].codepoints.len;
}

pub fn requestHighlight(self: *Buffer) void {
    if (self.file == null or self.extension == null) return;
    if (self.stopped.load(.acquire) or self.active.load(.acquire)) return;

    self.active.store(true, .release);
    self.pool.schedule(.from(&self.task));
}

pub fn fileUpdate(self: *Buffer, file: ?Io.File) !void {
    defer self.emitUpdate();

    self.rwlock.lock();
    defer self.rwlock.unlock();

    self.text.deinit();
    self.highlights.deinit(self.alloc);

    if (file) |f| {
        self.setState(.ready);
        self.file = try f.clone(self.alloc);
        //NOTE:
        //when the file changes we probably want to
        //reuse the same text buffer version and history
        self.text = try TextBuffer.initFromBytes(self.alloc, self.file.?.bytes);

        self.requestHighlight();
    } else {
        self.setState(.err);
    }
}

pub fn emitUpdate(self: *Buffer) void {
    global.state.emitGlobal(.{ .bufferUpdate = self.id });
}

pub fn stat(self: *Buffer) ?Stat {
    self.rwlock.lockShared();
    defer self.rwlock.unlockShared();
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

pub fn rows(self: *Buffer) usize {
    self.rwlock.lockShared();
    defer self.rwlock.unlockShared();

    return self.text.rows();
}

pub fn highlightTask(task: *ThreadPool.Task) void {
    const buffer: *Buffer = @alignCast(@fieldParentPtr("task", task));

    while (!buffer.stopped.load(.acquire)) {
        if (buffer.highlight() catch true) break;
    }

    buffer.active.store(false, .release);
    buffer.emitUpdate();
}

fn highlight(self: *Buffer) !bool {
    var session = try zintect.Session.init();
    defer session.deinit();

    const valid = try session.setSyntaxByExt(self.alloc, &self.runtime, self.extension.?);
    if (!valid) {
        std.log.debug("the extension is invalid: {?s}", .{self.extension});
    }

    var version: usize = 0;
    const raw = raw: {
        self.rwlock.lockShared();
        defer self.rwlock.unlockShared();

        version = self.text.version;

        break :raw try self.text.content.dupeLogicalSlice(self.alloc, 0, self.text.content.realLength());
    };
    defer self.alloc.free(raw);

    var iter = session.highlightIterator(&self.runtime, raw[0..], self.alloc);
    defer iter.deinit();

    var hl_rows = try std.ArrayList([]Span).initCapacity(self.alloc, 0);
    errdefer {
        for (hl_rows.items) |row| {
            if (row.len > 0) self.alloc.free(row);
        }
        hl_rows.deinit(self.alloc);
    }

    while (try iter.next()) |spans| {
        {
            self.rwlock.lockShared();
            defer self.rwlock.unlockShared();

            if (self.text.version != version) {
                for (hl_rows.items) |r| {
                    if (r.len > 0) self.alloc.free(r);
                }
                hl_rows.deinit(self.alloc);

                return false;
            }
        }

        var converted = try std.ArrayList(Span).initCapacity(self.alloc, 0);
        errdefer converted.deinit(self.alloc);

        for (spans) |span| {
            try converted.append(self.alloc, .{
                .start = span.start,
                .end = span.end,
                .color = span.color,
                .style = Style.fromSpan(span),
            });
        }
        try hl_rows.append(self.alloc, try converted.toOwnedSlice(self.alloc));
    }

    var next_highlights: Highlights = .{
        .rows = try hl_rows.toOwnedSlice(self.alloc),
    };
    errdefer next_highlights.deinit(self.alloc);

    self.rwlock.lock();
    defer self.rwlock.unlock();

    if (self.text.version != version) {
        return false;
    }

    self.highlights.deinit(self.alloc);
    self.highlights = next_highlights;

    return true;
}

pub const Span = struct {
    start: u32,
    end: u32,
    color: [4]u8,
    style: Style = .regular,
};

pub const Highlights = struct {
    rows: [][]Span = &.{},

    pub fn deinit(self: *Highlights, alloc: Allocator) void {
        for (self.rows) |row| {
            if (row.len > 0) alloc.free(row);
        }
        if (self.rows.len > 0) alloc.free(self.rows);
        self.* = .{};
    }

    pub fn visibleRows(self: *const Highlights, scroll_row: u64, max_rows: usize) []const []Span {
        const start = @min(std.math.cast(usize, scroll_row) orelse self.rows.len, self.rows.len);
        const count = @min(max_rows, self.rows.len - start);
        return self.rows[start .. start + count];
    }
};

pub const Snapshot = struct {
    row_count: usize,
    rows: []TextBuffer.Row,
    hl_rows: [][]Span,
};

pub fn snapshot(
    self: *Buffer,
    alloc: Allocator,
    scroll_row: u64,
    max_rows: usize,
) !Snapshot {
    self.rwlock.lockShared();
    defer self.rwlock.unlockShared();

    const src_rows = self.text.visibleRows(scroll_row, max_rows);
    const src_hl = self.highlights.visibleRows(scroll_row, max_rows);

    const text_rows = try alloc.alloc(TextBuffer.Row, src_rows.len);
    for (src_rows, 0..) |src, i| {
        text_rows[i] = .{
            .codepoints = if (src.codepoints.len == 0)
                &.{}
            else
                try alloc.dupe(u32, src.codepoints),
        };
    }

    const hl_rows = try alloc.alloc([]Span, src_hl.len);
    for (src_hl, 0..) |src, i| {
        hl_rows[i] = if (src.len == 0)
            &.{}
        else
            try alloc.dupe(Span, src);
    }

    return .{
        .row_count = self.text.rows(),
        .rows = text_rows,
        .hl_rows = hl_rows,
    };
}

test "buffer highlight results deinit cleanly" {
    const alloc = std.testing.allocator;

    var runtime = try zintect.Runtime.init();
    defer runtime.deinit();

    var buffer = try Buffer.init(alloc, .{
        .id = 1,
        .extension = try alloc.dupe(u8, "rs"),
        .runtime = runtime,
        .pool = undefined,
    });
    defer buffer.deinit();

    buffer.text.deinit();
    buffer.text = try TextBuffer.initFromBytes(alloc, "let value = 42;\nfn main() {}\n");

    try std.testing.expect(try buffer.highlight());
    try std.testing.expect(buffer.highlights.rows.len > 0);
}
