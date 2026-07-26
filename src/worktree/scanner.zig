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
const chunk_pool = @import("../chunk_pool.zig");
const ChunkAllocator = chunk_pool.ChunkAllocator;
const ChunkedPath = @import("../chunked_path.zig");
const RANGE_NODE_SIZE = ChunkedPath.RANGE_NODE_SIZE;
const CHUNK_SIZE = ChunkedPath.CHUNKS_SIZE;
const contants = @import("../contants.zig");
const MAX_PATH_LEN = contants.MAX_PATH_LEN;
const datastruct = @import("../datastruct.zig");
const Queue = datastruct.Queue;
const Mpsc = datastruct.Mpsc;
const StealingQueue = datastruct.StealingQueue;
const sch = @import("../scheduler.zig");
const BackgroundScheduler = sch.BackgroundScheduler;
const Executor = BackgroundScheduler.Executor;
const Context = BackgroundScheduler.Context;
const Scheduler = sch.Scheduler;
const tsk = @import("../tasks.zig");
const attr = @import("attr.zig");
const BulkAttr = attr.BulkAttr;
const Snapshot = @import("snapshot.zig");

const UPDATE_INTERVAL: Io.Duration = .fromMilliseconds(100);

const Scanner = @This();

pub const Updates = union(enum) {
    pub const Queue = Io.Queue(Updates);

    started: void,
    updated: struct {
        snapshot: Snapshot,
        scanning: bool,
    },
};

pub const Action = union(enum) {
    pub const Queue = Io.Queue(Action);

    initial_scan: void,
    scan_end: void,
};

io: Io,
gpa: Allocator,
snapshot: Snapshot,
timer: ?BackgroundScheduler.Cancelation,
workers: Workers,
action_buffer: [8]Action,
actions: Action.Queue,
updates_buffer: [8]Updates,
updates: Updates.Queue,
chunks: ChunkAllocator,

pub fn init(
    self: *Scanner,
    waker: tsk.Waker,
    abs_path: []const u8,
    gpa: Allocator,
    io: Io,
) !void {
    self.* = .{
        .io = io,
        .gpa = gpa,
        .action_buffer = undefined,
        .actions = undefined,
        .updates = undefined,
        .updates_buffer = undefined,
        .snapshot = undefined,
        .workers = undefined,
        .timer = null,
        .chunks = undefined,
    };

    self.workers.init(io);

    self.actions = .init(&self.action_buffer);
    self.updates = .init(&self.updates_buffer);

    try self.chunks.init(gpa, &.{
        .{ 1024 * 1024 * 1024, RANGE_NODE_SIZE },
        .{ 1024 * 1024 * 1024, CHUNK_SIZE },
    });
    errdefer self.chunks.deinit(gpa);

    try self.snapshot.init(abs_path, gpa, io);

    try self.actions.putOne(self.io, .initial_scan);
    try waker.wake();
}

pub fn deinit(self: *Scanner) void {
    if (self.timer) |timer| {
        timer.cancel();
    }
    self.workers.deinit();
    self.updates.close(self.io);
    self.actions.close(self.io);
    self.clearUpdates();
    self.snapshot.deinit();
    self.chunks.deinit(self.gpa);
}

pub fn clearUpdates(self: *Scanner) void {
    var buffer: [8]Updates = undefined;
    const updates = &self.updates;
    const len = updates.get(self.io, &buffer, 0) catch 0;
    if (len == 0) return;

    for (0..len) |idx| {
        switch (buffer[idx]) {
            .updated => |*updated| {
                updated.snapshot.deinit();
            },
            else => {},
        }
    }
}

pub fn handleActions(
    self: *Scanner,
    ctx: Context,
    waker: sch.Waker,
    res: anyerror!void,
) bool {
    res catch {
        self.deinit();
        return false;
    };

    self._handleActions(ctx, waker) catch |err| {
        std.log.err("Worktree Scanner err={}", .{err});
        return true;
    };

    return true;
}

fn _handleActions(
    self: *Scanner,
    ctx: Context,
    waker: sch.Waker,
) !void {
    while (self.workers.popEntry()) |entry| {
        self.snapshot.insert(entry.path, entry.meta);
    }

    var buffer: [8]Action = undefined;
    for (0..try self.actions.get(self.io, &buffer, 0)) |idx| {
        switch (buffer[idx]) {
            .initial_scan => try self.initialScan(waker, ctx),
            .scan_end => {
                if (self.timer) |timer| {
                    self.timer = null;
                    timer.cancel();
                }

                self.workers.deinit();

                try self.updates.putOne(self.io, .{
                    .updated = .{
                        .scanning = false,
                        .snapshot = try self.snapshot.clone(self.gpa),
                    },
                });

                try waker.wake();
            },
        }
    }
}

fn initialScan(
    self: *Scanner,
    waker: sch.Waker,
    ctx: Context,
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

    try self.updates.putOne(self.io, .started);
    try waker.wake();

    const cpu_count = try std.Thread.getCpuCount();

    try self.workers.start(self.gpa, @intCast(cpu_count));
    errdefer self.workers.deinit();

    self.timer = try ctx.scheduler.timer(timerCallback, .{ self, waker }, @intCast(UPDATE_INTERVAL.toMilliseconds()));

    const root_job = self.workers.createJob(path, null, null);
    self.workers.pushJob(0, root_job);

    for (0..cpu_count) |i| {
        try self.workers.group.concurrent(
            self.io,
            Scanner.scan,
            .{ self, @as(u32, @intCast(i)), ctx },
        );
    }
}

fn timerCallback(self: *Scanner, waker: sch.Waker, res: anyerror!void) bool {
    res catch return false;

    if (!self.workers.working) return false;

    self._timerCallback(waker) catch |err| {
        std.log.err("Scanner Timer err={}", .{err});
        return false;
    };

    return true;
}

fn _timerCallback(self: *Scanner, waker: sch.Waker) !void {
    try self.updates.putOne(self.io, .{
        .updated = .{
            .scanning = true,
            .snapshot = try self.snapshot.clone(self.gpa),
        },
    });

    try waker.wake();
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

pub const Entry = struct {
    path: ChunkedPath,
    meta: Snapshot.Meta,
    next: ?*Entry = null,
};

const Workers = struct {
    io: Io,
    group: Io.Group,
    arena: heap.ArenaAllocator,
    entries: Mpsc(Entry),

    chunks: ChunkAllocator,
    queue: StealingQueue(Job),

    working: bool,

    pub fn init(self: *Workers, io: Io) void {
        self.* = .{
            .io = io,
            .working = false,
            .group = .init,
            .arena = undefined,
            .entries = undefined,
            .chunks = undefined,
            .queue = .{},
        };
        self.entries.init();
    }

    pub fn start(self: *Workers, gpa: Allocator, workers: u32) !void {
        assert(!self.working);

        self.arena = .init(gpa);
        errdefer self.arena.deinit();
        const arena = self.arena.allocator();

        try self.chunks.init(arena, &.{
            .{ 1024 * 1024, @max(@sizeOf(Entry), @sizeOf(SharedFd)) },
            .{ 1024 * 1024, @sizeOf(Job) },
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
            std.log.err("Workers stop err={}", .{err});
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

    pub fn pushEntry(self: *Workers, path: ChunkedPath, meta: Snapshot.Meta) void {
        const alloc = self.chunks.allocator();

        const entry = alloc.create(Entry) catch @panic("Scanner Entry Overflow");
        entry.* = .{
            .path = path,
            .meta = meta,
        };
        self.entries.push(entry);
    }

    pub fn popEntry(self: *Workers) ?Entry {
        const pop = self.entries.pop() orelse return null;

        defer self.chunks.allocator().destroy(pop);

        return pop.*;
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
    ctx: Context,
) void {
    self._scan(worker_id, ctx) catch |err| {
        std.log.err("worker err: {}", .{err});
    };
}

pub fn _scan(
    self: *Scanner,
    worker_id: u32,
    ctx: Context,
) !void {
    const arena = self.workers.arena.allocator();
    const buffer = try arena.alignedAlloc(u8, .@"8", 64 * 1024);
    const ignore_buffer = try arena.alloc(u8, 1024 * 1024);

    while (self.workers.popJob(worker_id)) |job| {
        defer self.workers.finishJob(job);

        try self.scanDir(job, worker_id, buffer, ignore_buffer);

        if (self.workers.done()) {
            @branchHint(.unlikely);
            try self.actions.putOne(self.io, .scan_end);
        }

        try ctx.waker.wake();
    }
}

fn scanDir(
    self: *Scanner,
    job: *Job,
    worker_id: u32,
    buffer: []align(8) u8,
    ignore_buffer: []u8,
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
        const content = dir.readFile(self.io, ".gitignore", ignore_buffer) catch null;

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

        self.workers.pushEntry(path, .{
            .inode = entry.meta.inode,
            .mtime = .fromNanoseconds(@intCast(entry.meta.mtime_ns)),
            .size = entry.meta.size,
            .kind = entry.kind,
            .hidden = is_hidden,
            .ignored = ignored,
        });

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
