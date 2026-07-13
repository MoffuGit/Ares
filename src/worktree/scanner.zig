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

const UPDATE_INTERVAL: Io.Duration = if (builtin.mode == .Debug) .fromSeconds(5) else .fromMilliseconds(100);

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
arena: heap.ArenaAllocator,

snapshot: Snapshot,
path_store: ChunkedPathStore,
chunks: ChunkAllocator,

shared: SharedState,

action_buffer: [16]Action,
actions: Action.Queue,

updates_buffer: [8]Updates,
updates: Updates.Queue,

next_entry_id: atomic.Value(u64),
group: Io.Group,

waker: tsk.Waker,
entries: mpsc.Intrusive(Entry),

scanning: bool,

pub fn init(
    self: *Scanner,
    waker: tsk.Waker,
    abs_path: []const u8,
    gpa: Allocator,
    io: Io,
) !void {
    self.* = .{
        .scanning = true,
        .chunks = undefined,
        .waker = waker,
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
        .entries = undefined,
        .shared = undefined,
    };

    self.entries.init();

    try self.shared.init(io, gpa);
    errdefer self.shared.deinit();

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

    try self.snapshot.init(abs_root, root_name, self.chunks.allocator());
    try self.snapshot.insert(.{
        .id = self.next_entry_id.fetchAdd(1, .monotonic),
        .path = root_path,
    });

    try self.actions.putOne(self.io, .initial_scan);
    try self.waker.wake();
}

pub fn deinit(self: *Scanner) void {
    if (self.scanning) {
        self.shared.stop();
        self.group.await(self.io) catch |err| {
            std.log.err("{}", .{err});
        };
        self.shared.deinit();
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
    _: Context,
    waker: sch.Waker,
) !void {
    while (self.entries.pop()) |entry| {
        try self.snapshot.insert(.{
            .id = entry.id,
            .path = entry.path,
        });

        self.shared.destroyEntry(entry);
    }

    var buffer: [16]Action = undefined;
    for (0..try self.actions.get(self.io, &buffer, 0)) |idx| {
        switch (buffer[idx]) {
            .initial_scan => {
                assert(self.scanning);
                try self.initialScan(waker);
            },
            .scan_end => {
                self.scanning = false;
                self.shared.stop();

                try self.updates.putOne(self.io, .{ .updated = .{
                    .scanning = false,
                    .snapshot = try self.snapshot.clone(),
                } });

                try waker.wake();

                try self.group.await(self.io);
                self.shared.deinit();
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
) !void {
    const stat = try Io.Dir.statFile(
        .cwd(),
        self.io,
        self.snapshot.abs_root,
        .{},
    );

    if (stat.kind != .directory) return;

    try self.updates.putOne(self.io, .started);
    try waker.wake();

    const root_entry = self.snapshot.entries.first() orelse return;

    const job = self.shared.createJob();
    job.* = .{
        .path = root_entry.path,
    };

    try self.shared.pushJob(job);

    const cpu_count = try std.Thread.getCpuCount();

    for (0..cpu_count) |_| {
        try self.group.concurrent(
            self.io,
            Scanner.scan,
            .{self},
        );
    }
}

const SharedState = struct {
    arena: heap.ArenaAllocator,
    io: Io,
    mutex: Io.Mutex,
    queue: queue.Intrusive(Job),

    jobs: ChunkAllocator,
    entries: ChunkAllocator,

    pending_jobs: atomic.Value(u64),

    stopped: atomic.Value(bool),

    pub fn init(
        self: *SharedState,
        io: Io,
        child_allocator: Allocator,
    ) !void {
        self.* = .{
            .io = io,
            .arena = .init(child_allocator),
            .mutex = .init,
            .queue = .{},
            .jobs = undefined,
            .entries = undefined,
            .pending_jobs = .init(0),
            .stopped = .init(false),
        };
        errdefer self.arena.deinit();
        const arena = self.arena.allocator();

        try self.entries.initThreadSafe(io, arena, &.{
            .{ 1024 * 1024, @sizeOf(Entry) },
        });

        try self.jobs.initThreadSafe(io, arena, &.{
            .{ 1024 * 1024, @sizeOf(Job) },
        });
    }

    pub fn deinit(self: *SharedState) void {
        self.arena.deinit();
    }

    pub fn stop(self: *SharedState) void {
        self.stopped.store(true, .release);
    }

    pub fn createJob(self: *SharedState) *Job {
        _ = self.pending_jobs.fetchAdd(1, .monotonic);
        return self.jobs.threadSafeAllocator().create(Job) catch @panic("Scanner Job Overflow");
    }

    pub fn destroyJob(self: *SharedState, job: *Job) u64 {
        self.jobs.threadSafeAllocator().destroy(job);
        return self.pending_jobs.fetchSub(1, .acq_rel);
    }

    pub fn createEntry(self: *SharedState) *Entry {
        return self.entries.threadSafeAllocator().create(Entry) catch @panic("Scanner Entry Overflow");
    }

    pub fn destroyEntry(self: *SharedState, entry: *Entry) void {
        self.entries.threadSafeAllocator().destroy(entry);
    }

    pub fn pushJob(self: *SharedState, job: *Job) !void {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);

        self.queue.push(job);
    }

    pub fn popJob(self: *SharedState) ?*Job {
        self.mutex.lock(self.io) catch return null;
        defer self.mutex.unlock(self.io);

        return self.queue.pop();
    }
};

pub const Job = struct {
    path: ChunkedPath,
    fd: posix.fd_t = -1,
    next: ?*Job = null,
};

pub const Entry = struct {
    id: u64,
    path: ChunkedPath,
    next: ?*Entry = null,
};

pub fn scan(
    self: *Scanner,
) void {
    self._scan() catch |err| {
        std.log.err("worker err: {}", .{err});
    };
}

pub fn _scan(
    self: *Scanner,
) !void {
    var path_z: [MAX_PATH_LEN:0]u8 = undefined;

    while (!self.shared.stopped.load(.acquire)) {
        while (self.shared.popJob()) |job| {
            try self.scanDir(&path_z, job.path);

            const pending = self.shared.destroyJob(job);
            assert(pending > 0);

            if (pending == 1) {
                try self.actions.putOne(self.io, .scan_end);
            }

            try self.waker.wake();
        }
    }
}

fn scanDir(
    self: *Scanner,
    path_z: [:0]u8,
    parent_path: ChunkedPath,
) !void {
    const abs_root = self.snapshot.abs_root;
    const root_name = self.snapshot.root_name;
    const root_name_len: u32 = @intCast(root_name.len);
    const relative_len = parent_path.len - root_name_len;

    assert(path_z.len > abs_root.len + relative_len);

    @memcpy(path_z[0..abs_root.len], abs_root);
    var offset: usize = abs_root.len;
    var skip: usize = root_name.len;
    var it = parent_path.iterator();
    while (it.next()) |segment| {
        if (skip >= segment.len) {
            skip -= segment.len;
            continue;
        }
        const take = segment.len - skip;
        @memcpy(path_z[offset .. offset + take], segment[skip..]);
        offset += take;
        skip = 0;
    }
    path_z[offset] = 0;

    const dir = c.opendir(path_z.ptr) orelse return;
    defer _ = c.closedir(dir);

    const point = ".";
    const pointpoint = "..";

    while (c.readdir(dir)) |entry_raw| {
        if (self.shared.stopped.load(.acquire)) break;

        const entry: *const c.dirent = @ptrCast(@alignCast(entry_raw));
        const name = direntNameFromEntry(entry);

        if (std.mem.eql(u8, name, point) or std.mem.eql(u8, name, pointpoint)) continue;

        const suffix_len: u32 = 1 + @as(u32, @intCast(name.len));
        const new_len = parent_path.len + suffix_len;
        if (new_len > MAX_PATH_LEN) continue;

        var path: ChunkedPath = undefined;
        var suffix_buf: [MAX_PATH_LEN]u8 = undefined;
        suffix_buf[0] = '/';
        @memcpy(suffix_buf[1 .. 1 + name.len], name);
        const suffix = suffix_buf[0 .. 1 + name.len];

        path = self.path_store.append(parent_path, suffix, 1);

        const ptr = self.shared.createEntry();

        ptr.* = .{
            .path = path,
            .id = self.next_entry_id.fetchAdd(1, .monotonic),
        };

        self.entries.push(ptr);

        if (entry.type != c.DT.DIR) continue;

        const job = self.shared.createJob();
        job.* = .{
            .path = path,
        };

        try self.shared.pushJob(job);
    }
}

inline fn direntNameFromEntry(entry: *const c.dirent) []const u8 {
    const namlen: usize = @intCast(entry.namlen);
    return entry.name[0..namlen];
}
