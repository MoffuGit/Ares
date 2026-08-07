const std = @import("std");
const Io = std.Io;
const c = std.c;
const atomic = std.atomic;
const posix = std.posix;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const heap = std.heap;
const Timestamp = Io.Timestamp;
const builtin = @import("builtin");

const GitIgnore = @import("zlob").GitIgnore;

const App = @import("../app.zig");
const Context = App.Context;
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
const Dequeue = datastruct.Dequeue;
const global = @import("../global.zig");
const Loop = @import("../loop.zig");
const Completion = Loop.Completion;
const Waker = Loop.Waker;
const Worktree = @import("../worktree.zig");
const Event = Worktree.Event;
const attr = @import("attr.zig");
const BulkAttr = attr.BulkAttr;
const Snapshot = @import("snapshot.zig");

const UPDATE_INTERVAL_IN_MS = if (builtin.mode == .Debug) 2000 else 100;
const state = &global.state;
const log = std.log.scoped(.scanner);

const Scanner = @This();

io: Io,
gpa: Allocator,
arena: Allocator,
group: Io.Group,
snapshot: Snapshot,
mutex: Io.Mutex,
chunks: ChunkAllocator,
queue: Dequeue(Job),
last_update: atomic.Value(i64),

pub fn init(
    self: *Scanner,
    gpa: Allocator,
    arena: Allocator,
    io: Io,
) !void {
    self.* = .{
        .gpa = gpa,
        .arena = arena,
        .io = io,
        .snapshot = undefined,
        .mutex = .init,
        .chunks = undefined,
        .queue = undefined,
        .group = .init,
        .last_update = .init(Timestamp.now(io, .real).toMilliseconds()),
    };

    self.snapshot = try self.worktree().snapshot.clone(self.gpa);

    try self.chunks.init(self.arena, &.{
        .{ 1024 * 1024 * 1024, RANGE_NODE_SIZE },
        .{ 1024 * 1024 * 1024, CHUNK_SIZE },
        .{ 1024 * 1024, @sizeOf(Entry) },
        .{ 1024 * 1024, @sizeOf(Job) },
        .{ 1024 * 1024, @sizeOf(SharedFd) },
    });

    try self.queue.init(self.arena, @intCast(state.cpu_count));
    try self.group.concurrent(self.io, initialScan, .{self});
}

pub fn deinit(self: *Scanner) void {
    self.group.cancel(self.io);
    var iter = self.queue.iterator();
    while (iter.next()) |job| {
        job.finish(self.chunks.allocator(), self.io);
    }

    self.snapshot.deinit();
}

pub inline fn worktree(self: *Scanner) *Worktree {
    return @fieldParentPtr("scanner", self);
}

pub inline fn pushEvent(self: *Scanner, event: Event) !void {
    try self.worktree().events.putOne(self.io, event);
}

pub inline fn flushUpdates(self: *Scanner) !void {
    try self.worktree().waker.wake();
}

fn initialScan(self: *Scanner) !void {
    self._initialScan() catch |err| {
        log.err("Initial Scan err={}", .{err});
    };
}

fn _initialScan(
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

    {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);

        self.snapshot.insert(
            path,
            .{
                .inode = stat.inode,
                .size = stat.size,
                .mtime = stat.mtime,
                .kind = stat.kind,
                .hidden = false,
                .ignored = false,
                .state = .pending,
            },
        );
    }

    if (stat.kind != .directory) return;

    try self.pushEvent(.started);
    try self.flushUpdates();

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

pub const Entry = struct {
    path: ChunkedPath,
    meta: Snapshot.Meta,
    next: ?*Entry = null,
};

pub fn _scan(
    self: *Scanner,
    worker_id: u32,
) !void {
    errdefer self.queue.closed.store(true, .release);

    const chunks = self.chunks.allocator();
    var buffer: [64 * 1024]u8 = undefined;
    var batch: Queue(Entry) = .{};

    while (true) {
        const job = try self.queue.pop(self.io, worker_id);
        defer job.finish(chunks, self.io);

        try self.scanDir(job, worker_id, &buffer, &batch);

        if (self.queue.taskDone(self.io)) {
            @branchHint(.unlikely);

            try self.mutex.lock(self.io);
            defer self.mutex.unlock(self.io);

            try self.pushEvent(.{ .update = .{
                .scanning = false,
                .snapshot = try self.snapshot.clone(self.gpa),
            } });

            try self.flushUpdates();
        } else {
            const now = Timestamp.now(self.io, .real).toMilliseconds();
            const last = self.last_update.load(.acquire);

            if (now - last >= UPDATE_INTERVAL_IN_MS) {
                if (self.last_update.cmpxchgWeak(last, now, .acq_rel, .monotonic) == null) {
                    try self.mutex.lock(self.io);
                    defer self.mutex.unlock(self.io);

                    try self.pushEvent(.{ .update = .{
                        .scanning = true,
                        .snapshot = try self.snapshot.clone(self.gpa),
                    } });

                    try self.flushUpdates();
                }
            }
        }
    }
}

fn scanDir(
    self: *Scanner,
    job: *Job,
    worker_id: u32,
    buffer: []u8,
    batch: *Queue(Entry),
) !void {
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
            const gi = try GitIgnore.parse(self.arena, src);
            const node = try self.arena.create(IgnoreNode);
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
            return error.Closed;
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

        const new_entry = try chunks.create(Entry);
        new_entry.* = .{
            .path = path,
            .meta = .{
                .state = bkl: {
                    if (entry.kind == .directory) {
                        break :bkl if (is_hidden or ignored) .unloaded else .pending;
                    } else break :bkl .loaded;
                },
                .inode = entry.meta.inode,
                .mtime = .fromNanoseconds(@intCast(entry.meta.mtime_ns)),
                .size = entry.meta.size,
                .kind = entry.kind,
                .hidden = is_hidden,
                .ignored = ignored,
            },
        };
        batch.push(new_entry);

        if (is_dir and !(is_hidden or ignored)) {
            const new = try chunks.create(Job);
            new.* = .{
                .fd = null,
                .path = path,
                .ignore = effective_ignore,
            };
            jobs.push(new);
            count += 1;
        }
    }

    {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);

        while (batch.pop()) |entry| {
            self.snapshot.insert(entry.path, entry.meta);
            chunks.destroy(entry);
        }

        const dir_entry = self.snapshot.entries.get_mut(job.path) orelse unreachable;
        dir_entry.meta.state = .loaded;
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
