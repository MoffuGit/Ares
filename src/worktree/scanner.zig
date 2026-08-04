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
const StealingQueue = datastruct.StealingQueue;
const global = @import("../global.zig");
const Runner = @import("../runner.zig");
const attr = @import("attr.zig");
const BulkAttr = attr.BulkAttr;
const Snapshot = @import("snapshot.zig");

const log = std.log.scoped(.scanner);

const state = &global.state;
const UPDATE_INTERVAL: Io.Duration = .fromMilliseconds(100);

const Scanner = @This();

pub const Updates = union(enum) {
    started: void,
    updated: struct {
        snapshot: Snapshot,
        scanning: bool,
    },

    pub fn deinit(self: *Updates) void {
        switch (self.*) {
            .updated => |*updated| {
                updated.snapshot.deinit();
            },
            else => {},
        }
    }
};

pub const Entry = struct {
    path: ChunkedPath,
    meta: Snapshot.Meta,
    next: ?*Entry = null,
};

pub const Actions = MpscBounded(Action);

pub const Action = union(enum) {
    initial_scan: void,
    scan_end: void,
    new_entries: Queue(Entry),
};

io: Io,
gpa: Allocator,
snapshot: Snapshot,
workers: Workers,
actions: Actions,
chunks: ChunkAllocator,
runner: *Runner,

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
        .workers = undefined,
        .timer = null,
        .waker = undefined,
        .await = undefined,
        .chunks = undefined,
        .actions = undefined,
    };

    self.workers.init(io);

    self.actions = try .init(state.cpu_count + 2, 128, gpa);
    errdefer self.actions.deinit(gpa);

    try self.chunks.init(gpa, &.{
        .{ 1024 * 1024 * 1024, RANGE_NODE_SIZE },
        .{ 1024 * 1024 * 1024, CHUNK_SIZE },
    });
    errdefer self.chunks.deinit(gpa);

    try self.snapshot.init(abs_path, gpa, io);

    self.await, self.waker = try runner.await(handleActions, .{self});

    var producer = self.actions.register() orelse unreachable;
    defer producer.unregister();

    producer.push(.initial_scan);
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
    self.workers.deinit();
    self.actions.deinit(self.gpa);
    self.snapshot.deinit();
    self.chunks.deinit(self.gpa);
}

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
    var batch: Queue(Entry) = .{};
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
        self.workers.chunks.allocator().destroy(entry);
    }

    if (scan_end) {
        if (self.timer) |timer| {
            self.runner.cancel(timer);
            self.timer = null;
        }

        self.workers.deinit();

        const update = try self.runner.dispatch(self.subscription, Updates);
        update.* = .{
            .updated = .{
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

    const path: ChunkedPath = .new(self.snapshot.root_name, 0, self.chunks.allocator());

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

    const update = try self.runner.dispatch(self.subscription, Updates);
    update.* = .started;

    try self.workers.start(self.gpa, @intCast(state.cpu_count));
    errdefer self.workers.deinit();

    self.timer = try self.runner.timer(timerCallback, .{self}, @intCast(UPDATE_INTERVAL.toMilliseconds()));

    const root_job = self.workers.createJob(path, null, null);
    self.workers.pushJob(0, root_job);

    for (0..state.cpu_count) |i| {
        try self.workers.group.concurrent(
            self.io,
            Scanner.scan,
            .{ self, @as(u32, @intCast(i)) },
        );
    }
}

fn timerCallback(self: *Scanner, res: anyerror!void) bool {
    res catch return false;

    if (!self.workers.working) return false;

    self._timerCallback() catch |err| {
        log.err("Scanner Timer err={}", .{err});
        return false;
    };

    return true;
}

fn _timerCallback(self: *Scanner) !void {
    const update = try self.runner.dispatch(self.subscription, Updates);
    update.* = .{
        .updated = .{
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

const Workers = struct {
    io: Io,
    group: Io.Group,
    arena: heap.ArenaAllocator,
    chunks: ChunkAllocator,
    queue: StealingQueue(Job),

    working: bool,

    pub fn init(self: *Workers, io: Io) void {
        self.* = .{
            .io = io,
            .working = false,
            .group = .init,
            .arena = undefined,
            .chunks = undefined,
            .queue = .{},
        };
    }

    pub fn start(self: *Workers, gpa: Allocator, workers: u32) !void {
        assert(!self.working);

        self.arena = .init(gpa);
        errdefer self.arena.deinit();
        const arena = self.arena.allocator();

        try self.chunks.init(arena, &.{
            .{ 1024 * 1024, @sizeOf(Entry) },
            .{ 1024 * 1024, @sizeOf(Job) },
            .{ 1024 * 1024, @sizeOf(SharedFd) },
        });
        errdefer self.chunks.deinit(arena);

        try self.queue.init(arena, workers);

        self.working = true;
    }

    pub fn deinit(self: *Workers) void {
        if (!self.working) return;

        self.queue.closed.store(true, .release);
        self.queue.wakeAll(self.io);

        self.group.await(self.io) catch |err| {
            log.err("Workers stop err={}", .{err});
        };

        for (self.queue.queues) |*local| {
            while (local.queue.pop()) |job| {
                if (job.fd) |fd| {
                    const prev = fd.release();
                    assert(prev != 0);
                    if (prev == 1) fd.close(self.io);
                }
            }
        }

        self.arena.deinit();
        self.working = false;
    }

    pub fn sharedFd(self: *Workers, dir: Io.Dir, refs: u32) *SharedFd {
        const alloc = self.chunks.allocator();
        const shared = alloc.create(SharedFd) catch @panic("Scanner Job Overflow");
        shared.init(dir, refs);
        return shared;
    }

    pub fn createJob(
        self: *Workers,
        path: ChunkedPath,
        fd: ?*SharedFd,
        ignore: ?*const IgnoreNode,
    ) *Job {
        const alloc = self.chunks.allocator();
        const job = alloc.create(Job) catch @panic("Scanner Job Overflow");
        job.* = .{ .path = path, .fd = fd, .ignore = ignore };
        return job;
    }

    pub fn pushJob(self: *Workers, worker_id: u32, job: *Job) void {
        self.queue.push(self.io, worker_id, job);
    }

    pub fn popJob(self: *Workers, worker_id: u32) ?*Job {
        return self.queue.pop(self.io, worker_id);
    }

    pub fn finishJob(self: *Workers, job: *Job) void {
        const alloc = self.chunks.allocator();

        if (job.fd) |fd| {
            const prev = fd.release();

            assert(prev != 0);
            if (prev == 1) {
                fd.close(self.io);
                alloc.destroy(fd);
            }
        }
        self.chunks.allocator().destroy(job);
    }

    pub fn done(self: *Workers) bool {
        return self.queue.taskDone(self.io);
    }

    pub fn closed(self: *Workers) bool {
        return self.queue.closed.load(.acquire);
    }
};

pub fn scan(
    self: *Scanner,
    worker_id: u32,
) void {
    self._scan(worker_id) catch |err| {
        log.err("worker err: {}", .{err});
    };
}

pub fn _scan(
    self: *Scanner,
    worker_id: u32,
) !void {
    var buffer: [64 * 1024]u8 = undefined;
    var batch: Queue(Entry) = .{};

    while (self.workers.popJob(worker_id)) |job| {
        defer self.workers.finishJob(job);

        try self.scanDir(job, worker_id, &buffer, &batch);

        var producer = self.actions.register() orelse unreachable;
        defer producer.unregister();

        if (!batch.empty()) {
            @branchHint(.likely);
            producer.push(.{ .new_entries = batch });
            batch = .{};
        }

        if (self.workers.done()) {
            @branchHint(.unlikely);
            producer.push(.scan_end);
        }

        try self.waker.wake();
    }
}

fn scanDir(
    self: *Scanner,
    job: *Job,
    worker_id: u32,
    buffer: []u8,
    batch: *Queue(Entry),
) !void {
    const dir = bkl: {
        if (job.fd) |fd| {
            const len = job.path.basename(buffer);
            break :bkl try fd.dir.openDir(self.io, buffer[0..len], .{ .follow_symlinks = false, .iterate = true });
        }

        break :bkl try Io.Dir.openDirAbsolute(self.io, self.snapshot.abs_root, .{ .follow_symlinks = false, .iterate = true });
    };
    errdefer dir.close(self.io);

    const arena = self.workers.arena.allocator();
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
            self.workers.finishJob(j);
        }
    }

    while (try bulk.next()) |entry| {
        if (self.workers.closed()) {
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

        const new_entry = try self.workers.chunks.allocator().create(Entry);
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

        const new = self.workers.createJob(path, null, effective_ignore);
        jobs.push(new);
        count += 1;
    }

    if (count > 0) {
        const shared = self.workers.sharedFd(dir, count);

        while (jobs.pop()) |j| {
            j.fd = shared;
            self.workers.pushJob(worker_id, j);
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
