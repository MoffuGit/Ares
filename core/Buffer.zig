const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = @import("io/mod.zig");
const Stat = Io.Stat;
const global = @import("global.zig");
const TextBuffer = @import("Text.zig");
const ThreadPool = global.xev.ThreadPool;
const Style = @import("font/mod.zig").Style;
const zintect = @import("zintect");
const Highlights = @import("Highlights.zig");
pub const Span = Highlights.Span;

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

pub fn requestHighlight(self: *Buffer) void {
    if (self.file == null or self.extension == null) return;
    if (self.stopped.load(.acquire) or self.active.load(.acquire)) return;

    std.log.debug("dka;dsfkj", .{});
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

pub fn highlightTask(task: *ThreadPool.Task) void {
    const buffer: *Buffer = @alignCast(@fieldParentPtr("task", task));

    while (!buffer.stopped.load(.acquire)) {
        const res = buffer.highlight() catch {
            break;
        };
        if (res) break;
    }

    buffer.active.store(false, .release);
    buffer.emitUpdate();
}

fn highlight(self: *Buffer) !bool {
    var session = try zintect.Session.init();
    defer session.deinit();

    _ = session.setSyntaxByExt(&self.runtime, self.extension.?[0..]);

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

    var lines = try std.ArrayList([]Highlights.Span).initCapacity(self.alloc, 0);
    errdefer {
        for (lines.items) |line| {
            if (line.len > 0) self.alloc.free(line);
        }
        lines.deinit(self.alloc);
    }

    while (try iter.next()) |spans| {
        {
            self.rwlock.lockShared();
            defer self.rwlock.unlockShared();

            if (self.text.version != version) {
                for (lines.items) |l| {
                    if (l.len > 0) self.alloc.free(l);
                }
                lines.deinit(self.alloc);

                return false;
            }
        }

        var converted = try std.ArrayList(Highlights.Span).initCapacity(self.alloc, 0);
        errdefer converted.deinit(self.alloc);

        for (spans) |span| {
            try converted.append(self.alloc, .{
                .start = span.start,
                .end = span.end,
                .color = span.color,
                .style = Style.fromSpan(span),
            });
        }
        try lines.append(self.alloc, try converted.toOwnedSlice(self.alloc));
    }

    {
        self.rwlock.lock();
        self.rwlock.unlock();
        self.highlights.deinit(self.alloc);
        self.highlights.lines = lines.items;
    }

    return true;
}
