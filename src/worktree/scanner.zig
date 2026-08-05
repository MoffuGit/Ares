const std = @import("std");
const Io = std.Io;
const c = std.c;
const atomic = std.atomic;
const posix = std.posix;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const heap = std.heap;
const builtin = @import("builtin");

const GitIgnore = @import("zlob").GitIgnore;

const App = @import("../app.zig");
const Receiver = App.Receiver;
const chunk_pool = @import("../chunk_pool.zig");
const ChunkAllocator = chunk_pool.ChunkAllocator;
const ChunkedPath = @import("../chunked_path.zig");
const RANGE_NODE_SIZE = ChunkedPath.RANGE_NODE_SIZE;
const CHUNK_SIZE = ChunkedPath.CHUNKS_SIZE;
const constants = @import("../constants.zig");
const MAX_PATH_LEN = constants.MAX_PATH_LEN;
const datastruct = @import("../datastruct.zig");
const Queue = datastruct.Queue;
const MpscBounded = datastruct.MpscBounded;
const MpmcBounded = datastruct.MpmcBounded;
const global = @import("../global.zig");
const Runner = @import("../runner.zig");
const attr = @import("attr.zig");
const BulkAttr = attr.BulkAttr;
const Snapshot = @import("snapshot.zig");

const UPDATE_INTERVAL: Io.Duration = .fromMilliseconds(100);
const state = &global.state;
const log = std.log.scoped(.scanner);

const Scanner = @This();

io: Io,
gpa: Allocator,
arena: heap.ArenaAllocator,
group: Io.Group,
snapshot: Snapshot,
actions: Actions,
chunks: ChunkAllocator,
runner: *Runner,
queue: MpmcBounded(Job),

waker: Runner.Waker,
await: Runner.TaskId,
timer: ?Runner.TaskId,

subscription: Receiver,

pub fn init(
    self: *Scanner,
    runner: *Runner,
    subscription: Receiver,
    abs_path: []const u8,
    gpa: Allocator,
    io: Io,
) !void {
    self.* = .{
        .subscription = subscription,
        .runner = runner,
        .io = io,
        .gpa = gpa,
        .snapshot = undefined,
        .timer = null,
        .waker = undefined,
        .await = undefined,
        .chunks = undefined,
        .actions = undefined,
        .queue = undefined,
        .arena = .init(gpa),
        .group = .init,
    };

    const arena = self.arena.allocator();
    errdefer self.arena.deinit();

    self.actions = try .init(state.cpu_count + 2, 128, arena);

    try self.chunks.init(arena, &.{
        .{ 1024 * 1024 * 1024, RANGE_NODE_SIZE },
        .{ 1024 * 1024 * 1024, CHUNK_SIZE },
        .{ 1024 * 1024, @sizeOf(NewEntry) },
        .{ 1024 * 1024, @sizeOf(Job) },
        .{ 1024 * 1024, @sizeOf(SharedFd) },
    });

    try self.queue.init(arena, @intCast(state.cpu_count));
    try self.snapshot.init(abs_path, gpa, io);

    self.await, self.waker = try runner.await(handleActions, .{self});

    var producer = self.actions.register() orelse unreachable;
    defer producer.unregister();

    try producer.push(.initial_scan, self.io);
    try self.waker.wake();
}

pub fn drop(self: *Scanner) void {
    if (self.timer) |timer| {
        self.runner.cancel(timer);
    }
    self.runner.cancel(self.await);
    self.waker.close();
    self.runner.drop(self);
}

pub fn deinit(self: *Scanner) void {
    self.group.cancel(self.io);

    for (self.queue.queues) |*local| {
        while (local.queue.pop()) |job| {
            if (job.fd) |fd| {
                const prev = fd.release();
                assert(prev != 0);
                if (prev == 1) fd.close(self.io);
            }
        }
    }

    self.snapshot.deinit();
    self.arena.deinit();
}

pub const Event = union(enum) {
    started: void,
    update: struct {
        snapshot: Snapshot,
        scanning: bool,
    },

    pub fn deinit(self: *Event) void {
        switch (self.*) {
            .update => |*updated| {
                updated.snapshot.deinit();
            },
            else => {},
        }
    }
};

pub const NewEntry = struct {
    path: ChunkedPath,
    meta: Snapshot.Meta,
    next: ?*NewEntry = null,
};

pub const Actions = MpscBounded(Action);

pub const Action = union(enum) {
    initial_scan: void,
    scan_end: void,
    new_entries: Queue(NewEntry),
};

pub fn handleActions(self: *Scanner, res: anyerror!void) bool {
    res catch return false;

    self._handleActions() catch |err| {
        log.err("Worktree Scanner err={}", .{err});
        return true;
    };

    return true;
}

fn _handleActions(
    self: *Scanner,
) !void {
    const chunks = self.chunks.allocator();
    var batch: Queue(NewEntry) = .{};
    var scan_end = false;

    while (self.actions.pop()) |action| {
        switch (action) {
            .initial_scan => try self.initialScan(),
            .scan_end => scan_end = true,
            .new_entries => |b| batch.copy(&b),
        }
    }

    while (batch.pop()) |entry| {
        self.snapshot.insert(entry.path, entry.meta);
        chunks.destroy(entry);
    }

    if (scan_end) {
        if (self.timer) |timer| {
            self.runner.cancel(timer);
            self.timer = null;
        }

        const update = try self.runner.dispatch(self.subscription, Event);
        update.* = .{
            .update = .{
                .scanning = false,
                .snapshot = try self.snapshot.clone(self.gpa),
            },
        };
    }
}

fn initialScan(
    self: *Scanner,
) !void {
    const stat = try Io.Dir.statFile(
        .cwd(),
        self.io,
        self.snapshot.abs_root,
        .{},
    );

    const chunks = self.chunks.allocator();

    const path: ChunkedPath = .new(self.snapshot.root_name, 0, chunks);

    self.snapshot.insert(
        path,
        .{
            .inode = stat.inode,
            .size = stat.size,
            .mtime = stat.mtime,
            .kind = stat.kind,
            .hidden = false,
            .ignored = false,
        },
    );

    if (stat.kind != .directory) return;

    const update = try self.runner.dispatch(self.subscription, Event);
    update.* = .started;

    self.timer = try self.runner.timer(timerCallback, .{self}, @intCast(UPDATE_INTERVAL.toMilliseconds()));

    const root_job = chunks.create(Job) catch unreachable;
    root_job.* = .{ .path = path, .fd = null, .ignore = null };
    try self.queue.push(self.io, 0, root_job);

    for (0..state.cpu_count) |i| {
        try self.group.concurrent(
            self.io,
            Scanner.scan,
            .{ self, @as(u32, @intCast(i)) },
        );
    }
}

fn timerCallback(self: *Scanner, res: anyerror!void) bool {
    res catch return false;

    if (self.queue.closed.load(.acquire)) return false;

    self._timerCallback() catch |err| {
        log.err("Scanner Timer err={}", .{err});
        return false;
    };

    return true;
}

fn _timerCallback(self: *Scanner) !void {
    const update = try self.runner.dispatch(self.subscription, Event);
    update.* = .{
        .update = .{
            .scanning = true,
            .snapshot = try self.snapshot.clone(self.gpa),
        },
    };
}

const IgnoreNode = struct {
    gi: GitIgnore,
    relative_offset: u32,

    parent: ?*const IgnoreNode,
};

pub const Job = struct {
    path: ChunkedPath,
    fd: ?*SharedFd,
    ignore: ?*const IgnoreNode,
    next: ?*Job = null,

    pub fn finish(self: *Job, chunks: Allocator, io: Io) void {
        if (self.fd) |fd| {
            const prev = fd.release();

            assert(prev != 0);
            if (prev == 1) {
                fd.close(io);
                chunks.destroy(fd);
            }
        }

        chunks.destroy(self);
    }
};

const SharedFd = struct {
    dir: Io.Dir,
    refs: atomic.Value(u32),

    pub fn init(self: *SharedFd, dir: Io.Dir, refs: u32) void {
        self.* = .{
            .dir = dir,
            .refs = .init(refs),
        };
    }

    fn release(self: *SharedFd) u32 {
        return self.refs.fetchSub(1, .acq_rel);
    }

    fn close(self: *SharedFd, io: Io) void {
        self.dir.close(io);
    }
};

pub fn scan(
    self: *Scanner,
    worker_id: u32,
) void {
    self._scan(worker_id) catch |err| {
        switch (err) {
            error.Closed, error.Canceled => {},
            else => log.err("worker err: {}", .{err}),
        }
    };
}

pub fn _scan(
    self: *Scanner,
    worker_id: u32,
) !void {
    const chunks = self.chunks.allocator();
    var buffer: [64 * 1024]u8 = undefined;
    var batch: Queue(NewEntry) = .{};

    while (true) {
        const job = try self.queue.pop(self.io, worker_id);
        defer job.finish(chunks, self.io);

        try self.scanDir(job, worker_id, &buffer, &batch);

        var producer = self.actions.register() orelse unreachable;
        defer producer.unregister();

        if (!batch.empty()) {
            @branchHint(.likely);
            try producer.push(.{ .new_entries = batch }, self.io);
            batch = .{};
        }

        if (self.queue.taskDone(self.io)) {
            @branchHint(.unlikely);
            try producer.push(.scan_end, self.io);
        }

        try self.waker.wake();
    }
}

fn scanDir(
    self: *Scanner,
    job: *Job,
    worker_id: u32,
    buffer: []u8,
    batch: *Queue(NewEntry),
) !void {
    const arena = self.arena.allocator();
    const chunks = self.chunks.allocator();

    const dir = bkl: {
        if (job.fd) |fd| {
            const len = job.path.basename(buffer);
            break :bkl try fd.dir.openDir(self.io, buffer[0..len], .{ .follow_symlinks = false, .iterate = true });
        }

        break :bkl try Io.Dir.openDirAbsolute(self.io, self.snapshot.abs_root, .{ .follow_symlinks = false, .iterate = true });
    };
    errdefer dir.close(self.io);

    var effective_ignore: ?*const IgnoreNode = job.ignore;
    {
        const content = dir.readFile(self.io, ".gitignore", buffer) catch null;

        if (content) |src| {
            const gi = try GitIgnore.parse(arena, src);
            const node = try arena.create(IgnoreNode);
            node.* = .{
                .parent = job.ignore,
                .gi = gi,
                .relative_offset = job.path.len + 1,
            };
            effective_ignore = node;
        }
    }

    var bulk = BulkAttr.init(dir.handle, buffer, .{
        .size = true,
        .mtime = true,
        .inode = true,
    });

    const parent_path = job.path;

    var jobs: Queue(Job) = .{};
    var count: u32 = 0;
    errdefer {
        while (jobs.pop()) |j| {
            j.finish(chunks, self.io);
        }
    }

    while (try bulk.next()) |entry| {
        if (self.queue.closed.load(.acquire)) {
            @branchHint(.unlikely);
            break;
        }

        const name = entry.name;
        const is_dir = entry.kind == .directory;
        const is_hidden = name.len > 0 and name[0] == '.';

        var suffix_buf: [MAX_PATH_LEN]u8 = undefined;
        suffix_buf[0] = '/';
        @memcpy(suffix_buf[1 .. 1 + name.len], name);
        const suffix = suffix_buf[0 .. 1 + name.len];

        const path: ChunkedPath = .extend(parent_path, suffix, 1, self.chunks.allocator());

        var path_buf: [MAX_PATH_LEN]u8 = undefined;
        const len = path.read(&path_buf);
        const ignored = isIgnored(effective_ignore, path_buf[0..len], name, is_dir);

        const new_entry = try chunks.create(NewEntry);
        new_entry.* = .{
            .path = path,
            .meta = .{
                .inode = entry.meta.inode,
                .mtime = .fromNanoseconds(@intCast(entry.meta.mtime_ns)),
                .size = entry.meta.size,
                .kind = entry.kind,
                .hidden = is_hidden,
                .ignored = ignored,
            },
        };
        batch.push(new_entry);

        if (is_hidden or ignored or !is_dir) continue;

        const new = try chunks.create(Job);
        new.* = .{
            .fd = null,
            .path = path,
            .ignore = effective_ignore,
        };
        jobs.push(new);
        count += 1;
    }

    if (count > 0) {
        const shared = try chunks.create(SharedFd);
        shared.* = .{
            .dir = dir,
            .refs = .init(count),
        };

        while (jobs.pop()) |j| {
            j.fd = shared;
            try self.queue.push(self.io, worker_id, j);
        }
    } else {
        dir.close(self.io);
    }
}

fn isIgnored(
    start: ?*const IgnoreNode,
    path: []const u8,
    basename: []const u8,
    is_dir: bool,
) bool {
    var node = start;
    while (node) |n| : (node = n.parent) {
        if (n.gi.is_empty) continue;

        if (n.gi.checkWithBasename(
            path[n.relative_offset..],
            basename,
            is_dir,
        )) |verdict| {
            return verdict;
        }
    }
    return false;
}
