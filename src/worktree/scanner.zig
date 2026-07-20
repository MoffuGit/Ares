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
const chunked_path = @import("../chunked_path.zig");
const ChunkedPath = chunked_path.ChunkedPath;
const ChunkedPathStore = chunked_path.ChunkedPathStore;
const contants = @import("../contants.zig");
const MAX_PATH_LEN = contants.MAX_PATH_LEN;
const datastruct = @import("../datastruct.zig");
const queue = datastruct.queue;
const mpsc = datastruct.mpsc;
const stealing = datastruct.stealing;
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
    reclaim: Snapshot,
};

io: Io,
gpa: Allocator,
arena: heap.ArenaAllocator,

snapshot: Snapshot,
path_store: ChunkedPathStore,
chunks: ChunkAllocator,

shared: ?*SharedState,
timer: ?BackgroundScheduler.Cancelation = null,

action_buffer: [8]Action,
actions: Action.Queue,

updates_buffer: [8]Updates,
updates: Updates.Queue,

next_entry_id: atomic.Value(u64),
group: Io.Group,

pub fn init(
    self: *Scanner,
    waker: tsk.Waker,
    abs_path: []const u8,
    gpa: Allocator,
    io: Io,
) !void {
    self.* = .{
        .gpa = gpa,
        .chunks = undefined,
        .group = .init,
        .io = io,
        .arena = .init(gpa),
        .action_buffer = undefined,
        .updates_buffer = undefined,
        .actions = undefined,
        .updates = undefined,
        .next_entry_id = .init(0),
        .snapshot = undefined,
        .path_store = undefined,
        .shared = null,
        .timer = null,
    };

    const arena = self.arena.allocator();
    errdefer self.arena.deinit();

    const abs_root = try arena.dupe(u8, abs_path);
    const root_name = try arena.dupe(u8, std.fs.path.basename(abs_root));

    self.actions = .init(&self.action_buffer);
    self.updates = .init(&self.updates_buffer);

    try self.path_store.init(
        io,
        arena,
        .{
            .chunk_capacity = 1024 * 1024,
            .inline_capacity = 1024 * 1024,
        },
    );

    try self.chunks.init(arena, &.{.{
        1024 * 1024, Snapshot.NODE_SIZE,
    }});

    try self.snapshot.init(abs_root, root_name, self.chunks.allocator());

    try self.actions.putOne(self.io, .initial_scan);
    try waker.wake();
}

pub fn deinit(self: *Scanner) void {
    if (self.timer) |timer| {
        timer.cancel();
        self.timer = null;
    }

    if (self.shared) |shared| {
        shared.stop();
        self.group.await(self.io) catch |err| {
            std.log.err("{}", .{err});
        };
        shared.deinit();
        self.shared = null;
    }

    self.updates.close(self.io);
    self.actions.close(self.io);

    self.arena.deinit();
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
        self.deinit();

        std.log.err("Worktree Scanner err={}", .{err});
        return false;
    };

    return true;
}

fn _handleActions(
    self: *Scanner,
    ctx: Context,
    waker: sch.Waker,
) !void {
    if (self.shared) |shared| {
        const alloc = shared.allocator();

        while (shared.entries.pop()) |entry| {
            try self.snapshot.insert(entry.data);

            alloc.destroy(entry);
        }
    }

    var buffer: [8]Action = undefined;
    for (0..try self.actions.get(self.io, &buffer, 0)) |idx| {
        switch (buffer[idx]) {
            .initial_scan => {
                try self.initialScan(waker, ctx);

                if (builtin.mode != .Debug) {
                    self.timer = try ctx.scheduler.timer(
                        timerCallback,
                        .{ self, waker },
                        @as(u64, @intCast(UPDATE_INTERVAL.toMilliseconds())),
                    );
                }
            },
            .scan_end => {
                if (self.timer) |timer| {
                    self.timer = null;
                    timer.cancel();
                }

                if (self.shared) |shared| {
                    self.shared = null;

                    shared.stop();
                    try self.group.await(self.io);
                    shared.deinit();
                }

                try self.updates.putOne(self.io, .{
                    .updated = .{
                        .scanning = false,
                        .snapshot = try self.snapshot.clone(),
                    },
                });

                try waker.wake();
            },
            .reclaim => |*snapshot| {
                snapshot.deinit();
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

    try self.snapshot.insert(.{
        .id = self.next_entry_id.fetchAdd(1, .monotonic),
        .path = self
            .path_store
            .put(self.snapshot.root_name, 0),
        .inode = stat.inode,
        .size = stat.size,
        .mtime = stat.mtime,
        .kind = stat.kind,
        .hidden = false,
        .ignored = false,
    });

    if (stat.kind != .directory) return;

    const entry = self.snapshot.entries.first() orelse @panic("Impossible");

    try self.updates.putOne(self.io, .started);
    try waker.wake();

    const arena = self.arena.allocator();
    const cpu_count = try std.Thread.getCpuCount();

    const shared = try arena.create(SharedState);
    try shared.init(self.io, self.gpa, cpu_count);

    errdefer {
        shared.deinit();
        self.shared = null;
    }

    self.shared = shared;

    const job = shared.createJob();
    job.* = .{
        .path = entry.path,
        .fd = null,
    };

    shared.queue.push(self.io, 0, job);

    for (0..cpu_count) |i| {
        try self.group.concurrent(
            self.io,
            Scanner.scan,
            .{ self, @as(u32, @intCast(i)), ctx },
        );
    }
}

fn timerCallback(self: *Scanner, waker: sch.Waker, res: anyerror!void) bool {
    res catch return false;

    if (self.shared == null) return false;

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
            .snapshot = try self.snapshot.clone(),
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
    next: ?*Job = null,
    ignore: ?*const IgnoreNode = null,
};

const SharedFd = struct {
    dir: Io.Dir,
    refs: atomic.Value(u32),

    fn release(self: *SharedFd) u32 {
        return self.refs.fetchSub(1, .acq_rel);
    }

    fn close(self: *SharedFd, io: Io) void {
        self.dir.close(io);
    }
};

pub const Entry = struct {
    data: Snapshot.Entry,
    next: ?*Entry = null,
};

const SharedState = struct {
    io: Io,
    entries: mpsc.Intrusive(Entry),
    arena: heap.ArenaAllocator,

    queue: stealing.StealingQueue(Job),
    chunks: ChunkAllocator,

    pub fn init(
        self: *SharedState,
        io: Io,
        child_allocator: Allocator,
        threads: usize,
    ) !void {
        self.* = .{
            .io = io,
            .entries = undefined,
            .arena = .init(child_allocator),
            .queue = .{},
            .chunks = undefined,
        };
        self.entries.init();

        errdefer self.arena.deinit();
        const arena = self.arena.allocator();

        try self.queue.init(arena, @intCast(threads));

        try self.chunks.init(arena, &.{
            .{ 1024 * 1024, @max(@sizeOf(Entry), @sizeOf(Job), @sizeOf(SharedFd)) },
        });
    }

    pub fn deinit(self: *SharedState) void {
        for (self.queue.queues) |*local| {
            while (local.queue.pop()) |job| {
                self.destroyJob(job);
            }
        }
        self.arena.deinit();
    }

    pub fn stop(self: *SharedState) void {
        self.queue.closed.store(true, .release);
        self.queue.wakeAll(self.io);
    }

    pub fn allocator(self: *SharedState) Allocator {
        return self.chunks.allocator();
    }

    pub fn createJob(self: *SharedState) *Job {
        return self.chunks.allocator().create(Job) catch @panic("Scanner Job Overflow");
    }

    pub fn destroyJob(self: *SharedState, job: *Job) void {
        if (job.fd) |fd| {
            const prev = fd.release();

            assert(prev != 0);
            if (prev == 1) {
                fd.close(self.io);
                self.destroySharedFd(fd);
            }
        }
        self.chunks.allocator().destroy(job);
    }

    pub fn createSharedFd(self: *SharedState) *SharedFd {
        return self.chunks.allocator().create(SharedFd) catch @panic("Scanner SharedFd Overflow");
    }

    pub fn destroySharedFd(self: *SharedState, ref: *SharedFd) void {
        self.chunks.allocator().destroy(ref);
    }

    pub fn createEntry(self: *SharedState) *Entry {
        return self.chunks.allocator().create(Entry) catch @panic("Scanner Entry Overflow");
    }

    pub fn destroyEntry(self: *SharedState, entry: *Entry) void {
        self.chunks.allocator().destroy(entry);
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
    const shared = self.shared orelse return;
    const buffer = try shared.arena.allocator().alignedAlloc(u8, .@"8", 64 * 1024);
    const ignore_buffer = try shared.arena.allocator().alloc(u8, 1024 * 1024);

    while (shared.queue.pop(self.io, worker_id)) |job| {
        defer shared.destroyJob(job);

        try self.scanDir(job, worker_id, shared, buffer, ignore_buffer);

        if (shared.queue.taskDone(self.io)) {
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
    shared: *SharedState,
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

    const arena = shared.arena.allocator();
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

    var jobs: queue.Intrusive(Job) = .{};

    var pending_count: u32 = 0;
    errdefer {
        while (jobs.pop()) |j| {
            shared.destroyJob(j);
        }
    }

    while (try bulk.next()) |entry| {
        if (shared.queue.closed.load(.acquire)) {
            @branchHint(.unlikely);
            break;
        }

        const name = entry.name;
        const is_hidden = name.len > 0 and name[0] == '.';
        const is_dir = entry.kind == .directory;

        var suffix_buf: [MAX_PATH_LEN]u8 = undefined;
        suffix_buf[0] = '/';
        @memcpy(suffix_buf[1 .. 1 + name.len], name);
        const suffix = suffix_buf[0 .. 1 + name.len];

        const path: ChunkedPath = self.path_store.append(parent_path, suffix, 1);

        var path_buf: [MAX_PATH_LEN]u8 = undefined;
        const relative = path.write(&path_buf);
        const ignored = isIgnored(effective_ignore, path_buf[0..relative], name, is_dir);

        const ptr = shared.createEntry();

        ptr.* = .{
            .data = .{
                .path = path,
                .id = self.next_entry_id.fetchAdd(1, .monotonic),
                .inode = entry.meta.inode,
                .mtime = .fromNanoseconds(@intCast(entry.meta.mtime_ns)),
                .size = entry.meta.size,
                .kind = entry.kind,
                .hidden = is_hidden,
                .ignored = ignored,
            },
        };

        shared.entries.push(ptr);

        if (is_hidden or ignored or !is_dir) continue;

        const new = shared.createJob();
        new.* = .{
            .path = path,
            .fd = null,
            .ignore = effective_ignore,
        };

        jobs.push(new);
        pending_count += 1;
    }

    if (pending_count > 0) {
        const shared_fd = shared.createSharedFd();
        shared_fd.* = .{
            .dir = dir,
            .refs = .init(pending_count),
        };

        while (jobs.pop()) |j| {
            j.fd = shared_fd;
            shared.queue.push(self.io, worker_id, j);
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
