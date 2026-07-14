const std = @import("std");
const Io = std.Io;
const c = std.c;
const atomic = std.atomic;
const posix = std.posix;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const heap = std.heap;
const builtin = @import("builtin");

const App = @import("../app.zig");
const attr = @import("attr.zig");
const BulkScanner = attr.BulkScanner;
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
const sch = @import("../scheduler.zig");
const BackgroundScheduler = sch.BackgroundScheduler;
const Executor = BackgroundScheduler.Executor;
const Context = BackgroundScheduler.Context;
const Scheduler = sch.Scheduler;
const tsk = @import("../tasks.zig");
const Snapshot = @import("snapshot.zig");

//TODO: use the existing Entry definition on snapshot
pub const Entry = struct {
    id: u64,
    path: ChunkedPath,
    size: u64,
    mtime: Io.Timestamp,
    inode: u64,
    kind: Io.File.Kind,
    next: ?*Entry = null,
};

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

    const root_path = self.path_store.put(root_name, 0);

    try self.chunks.init(arena, &.{.{
        1024 * 1024, Snapshot.NODE_SIZE,
    }});

    const stat = try Io.Dir.statFile(
        .cwd(),
        self.io,
        abs_root,
        .{},
    );

    try self.snapshot.init(abs_root, root_name, self.chunks.allocator());
    try self.snapshot.insert(.{
        .id = self.next_entry_id.fetchAdd(1, .monotonic),
        .path = root_path,
        .inode = stat.inode,
        .size = stat.size,
        .mtime = stat.mtime,
        .kind = stat.kind,
    });

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
    self._handleActions(ctx, waker) catch {
        self.deinit();
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
            try self.snapshot.insert(.{
                .id = entry.id,
                .path = entry.path,
                .size = entry.size,
                .inode = entry.inode,
                .mtime = entry.mtime,
                .kind = entry.kind,
            });

            alloc.destroy(entry);
        }
    }

    var buffer: [8]Action = undefined;
    for (0..try self.actions.get(self.io, &buffer, 0)) |idx| {
        switch (buffer[idx]) {
            .initial_scan => {
                try self.initialScan(waker, ctx.waker);
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
                    timer.cancel();
                    self.timer = null;
                }

                if (self.shared) |shared| {
                    shared.stop();
                    try self.group.await(self.io);
                    shared.deinit();
                    self.shared = null;
                }

                try self.updates.putOne(self.io, .{ .updated = .{
                    .scanning = false,
                    .snapshot = try self.snapshot.clone(),
                } });

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
    bg_waker: tsk.Waker,
) !void {
    const entry = self.snapshot.entries.first() orelse return;

    if (entry.kind != .directory) return;

    try self.updates.putOne(self.io, .started);
    try waker.wake();

    const arena = self.arena.allocator();
    const cpu_count = try std.Thread.getCpuCount();

    const shared = try arena.create(SharedState);
    try shared.init(self.io, self.gpa, cpu_count, bg_waker);
    errdefer {
        shared.deinit();
        self.shared = null;
    }

    self.shared = shared;

    const dir: Io.Dir = try .openDirAbsolute(
        self.io,
        self.snapshot.abs_root,
        .{ .follow_symlinks = false, .iterate = true },
    );

    const job = shared.createJob();
    job.* = .{
        .path = entry.path,
        .dir = dir,
    };

    shared.queue.push(self.io, 0, job);

    for (0..cpu_count) |i| {
        try self.group.concurrent(
            self.io,
            Scanner.scan,
            .{ self, @as(u32, @intCast(i)) },
        );
    }
}

fn timerCallback(self: *Scanner, waker: sch.Waker, res: anyerror!void) bool {
    res catch return false;
    if (self.shared == null) return false;

    const snapshot = self.snapshot.clone() catch return true;
    self.updates.putOne(self.io, .{ .updated = .{
        .scanning = true,
        .snapshot = snapshot,
    } }) catch return true;

    waker.wake() catch return true;

    return true;
}

//SOURCE: https://github.com/dmtrKovalenko/zlob/tree/main
//LICENSE: [ZLOB]

pub const Job = struct {
    path: ChunkedPath,
    dir: Io.Dir,
    next: ?*Job = null,
};

const Queue = struct {
    mutex: Io.Mutex = .init,
    queue: queue.Intrusive(Job) = .{},
    approx_len: atomic.Value(usize) = .init(0),
};

const SharedQueue = struct {
    queues: []Queue = &.{},
    wait_mutex: Io.Mutex = .init,
    cond: Io.Condition = .init,
    queued: atomic.Value(usize) = .init(0),
    outstanding: atomic.Value(usize) = .init(0),
    closed: atomic.Value(bool) = .init(false),

    pub fn init(q: *SharedQueue, arena: Allocator, workers: u32) !void {
        const n: usize = @max(1, @as(usize, @intCast(workers)));
        q.queues = try arena.alloc(Queue, n);
        for (q.queues) |*local| local.* = .{};
    }

    pub fn push(q: *SharedQueue, io: Io, worker_id: u32, job: *Job) void {
        const local = &q.queues[q.localIndex(worker_id)];
        local.mutex.lockUncancelable(io);
        local.queue.push(job);
        _ = local.approx_len.fetchAdd(1, .release);
        _ = q.outstanding.fetchAdd(1, .release);
        const queued_before = q.queued.fetchAdd(1, .release);
        local.mutex.unlock(io);
        if (queued_before < q.queues.len) q.wakeOne(io);
    }

    pub fn pop(q: *SharedQueue, io: Io, worker_id: u32) ?*Job {
        const home = q.localIndex(worker_id);
        while (true) {
            if (q.popFrom(io, home)) |job| return job;
            if (q.steal(io, home)) |job| return job;
            if (q.closed.load(.acquire)) return null;

            q.wait_mutex.lockUncancelable(io);
            while (q.queued.load(.acquire) == 0 and !q.closed.load(.acquire)) {
                q.cond.waitUncancelable(io, &q.wait_mutex);
            }
            q.wait_mutex.unlock(io);
        }
    }

    pub fn taskDone(q: *SharedQueue, io: Io) bool {
        if (q.outstanding.fetchSub(1, .acq_rel) == 1) {
            q.closed.store(true, .release);
            q.wakeAll(io);
            return true;
        }
        return false;
    }

    pub fn wakeAll(q: *SharedQueue, io: Io) void {
        q.wait_mutex.lockUncancelable(io);
        defer q.wait_mutex.unlock(io);
        q.cond.broadcast(io);
    }

    fn wakeOne(q: *SharedQueue, io: Io) void {
        q.wait_mutex.lockUncancelable(io);
        defer q.wait_mutex.unlock(io);
        q.cond.signal(io);
    }

    fn localIndex(q: *SharedQueue, worker_id: u32) usize {
        return @as(usize, @intCast(worker_id)) % q.queues.len;
    }

    fn popFrom(q: *SharedQueue, io: Io, index: usize) ?*Job {
        const local = &q.queues[index];
        if (local.approx_len.load(.acquire) == 0) return null;
        local.mutex.lockUncancelable(io);
        defer local.mutex.unlock(io);
        const job = local.queue.pop() orelse return null;
        _ = local.approx_len.fetchSub(1, .release);
        _ = q.queued.fetchSub(1, .acq_rel);
        return job;
    }

    fn steal(q: *SharedQueue, io: Io, home: usize) ?*Job {
        var offset: usize = 1;
        while (offset < q.queues.len) : (offset += 1) {
            const index = (home + offset) % q.queues.len;
            if (q.queues[index].approx_len.load(.acquire) == 0) continue;
            if (q.popFrom(io, index)) |job| return job;
        }
        return null;
    }

    fn deinit(self: *SharedQueue, io: Io) void {
        for (self.queues) |*local| {
            while (local.queue.pop()) |job| {
                job.dir.close(io);
            }
        }
    }
};

const SharedState = struct {
    io: Io,
    entries: mpsc.Intrusive(Entry),
    arena: heap.ArenaAllocator,

    queue: SharedQueue,
    chunks: ChunkAllocator,
    waker: tsk.Waker,

    pub fn init(
        self: *SharedState,
        io: Io,
        child_allocator: Allocator,
        threads: usize,
        waker: tsk.Waker,
    ) !void {
        self.* = .{
            .io = io,
            .entries = undefined,
            .arena = .init(child_allocator),
            .queue = .{},
            .chunks = undefined,
            .waker = waker,
        };
        self.entries.init();

        errdefer self.arena.deinit();
        const arena = self.arena.allocator();

        try self.queue.init(arena, @intCast(threads));

        try self.chunks.init(arena, &.{
            .{ 1024 * 1024, @max(@sizeOf(Entry), @sizeOf(Job)) },
        });
    }

    pub fn deinit(self: *SharedState) void {
        self.queue.deinit(self.io);
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
        self.chunks.allocator().destroy(job);
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
) void {
    self._scan(worker_id) catch |err| {
        std.log.err("worker err: {}", .{err});
    };
}

pub fn _scan(
    self: *Scanner,
    worker_id: u32,
) !void {
    const shared = self.shared orelse return;
    const buffer = try shared.arena.allocator().alignedAlloc(u8, .@"8", 64 * 1024);

    while (shared.queue.pop(self.io, worker_id)) |job| {
        try self.scanDir(job, worker_id, shared, buffer);

        shared.destroyJob(job);

        if (shared.queue.taskDone(self.io)) {
            try self.actions.putOne(self.io, .scan_end);
        }

        try shared.waker.wake();
    }
}

fn scanDir(
    self: *Scanner,
    job: *Job,
    worker_id: u32,
    shared: *SharedState,
    buffer: []align(8) u8,
) !void {
    const dir = job.dir;
    defer dir.close(self.io);

    var bulk = BulkScanner.init(dir.handle, buffer, .{
        .size = true,
        .mtime = true,
        .inode = true,
    });

    const parent_path = job.path;

    while (try bulk.next()) |entry| {
        if (shared.queue.closed.load(.acquire)) break;

        const name = entry.name;

        const suffix_len: u32 = 1 + @as(u32, @intCast(name.len));
        const new_len = parent_path.len + suffix_len;
        if (new_len > MAX_PATH_LEN) continue;

        var path: ChunkedPath = undefined;
        var suffix_buf: [MAX_PATH_LEN]u8 = undefined;
        suffix_buf[0] = '/';
        @memcpy(suffix_buf[1 .. 1 + name.len], name);
        const suffix = suffix_buf[0 .. 1 + name.len];

        path = self.path_store.append(parent_path, suffix, 1);

        const ptr = shared.createEntry();

        ptr.* = .{
            .path = path,
            .id = self.next_entry_id.fetchAdd(1, .monotonic),
            .inode = entry.meta.inode,
            .mtime = .fromNanoseconds(@intCast(entry.meta.mtime_ns)),
            .size = entry.meta.size,
            .kind = entry.kind,
        };

        shared.entries.push(ptr);

        if (entry.kind != .directory) continue;

        const new_dir = try dir.openDir(self.io, name, .{ .follow_symlinks = false, .iterate = true });

        const new = shared.createJob();
        new.* = .{
            .dir = new_dir,
            .path = path,
        };

        shared.queue.push(self.io, worker_id, new);
    }
}
