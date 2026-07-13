const std = @import("std");
const Io = std.Io;
const c = std.c;
const atomic = std.atomic;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const heap = std.heap;
const builtin = @import("builtin");

const App = @import("../app.zig");
const chunked_path = @import("../chunked_path.zig");
const ChunkedPath = chunked_path.ChunkedPath;
const ChunkedPathStore = chunked_path.ChunkedPathStore;
const contants = @import("../contants.zig");
const MAX_PATH_LEN = contants.MAX_PATH_LEN;
const sch = @import("../scheduler.zig");
const BackgroundScheduler = sch.BackgroundScheduler;
const Executor = BackgroundScheduler.Executor;
const Context = BackgroundScheduler.Context;
const Scheduler = sch.Scheduler;
const tsk = @import("../tasks.zig");
const Snapshot = @import("snapshot.zig");
const Entry = Snapshot.Entry;

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
    initial_scan_end: void,
    entries: []Entry,
};

io: Io,
mutex: Io.Mutex,
arena: heap.ArenaAllocator,
gpa: Allocator,
snapshot: Snapshot,
store: ChunkedPathStore,
action_buffer: [16]Action,
actions: Action.Queue,

updates_buffer: [8]Updates,
updates: Updates.Queue,

workers: ?[]Worker,
jobs_buffer: []Worker.Job,
jobs: Io.Queue(Worker.Job),

next_entry_id: atomic.Value(u64),
pending_jobs: atomic.Value(u64),

group: Io.Group,

waker: tsk.Waker,

pub fn init(
    self: *Scanner,
    waker: tsk.Waker,
    abs_path: []const u8,
    gpa: Allocator,
    io: Io,
) !void {
    self.* = .{
        .waker = waker,
        .group = .init,
        .io = io,
        .gpa = gpa,
        .arena = .init(gpa),
        .action_buffer = undefined,
        .updates_buffer = undefined,
        .jobs_buffer = undefined,
        .actions = undefined,
        .updates = undefined,
        .jobs = undefined,
        .next_entry_id = .init(0),
        .pending_jobs = .init(0),
        .snapshot = undefined,
        .mutex = .init,
        .store = undefined,
        .workers = null,
    };

    const arena = self.arena.allocator();
    errdefer self.arena.deinit();

    const abs_root = try arena.dupe(u8, abs_path);
    const root_name = try arena.dupe(u8, std.fs.path.basename(abs_root));

    self.jobs_buffer = try arena.alloc(Worker.Job, 128);

    self.actions = .init(&self.action_buffer);
    self.updates = .init(&self.updates_buffer);
    self.jobs = .init(self.jobs_buffer);

    try self.store.init(arena, .{ .chunk_capacity = 1024 * 1024, .inline_capacity = 1024 * 1024 });

    const root_path = self.store.put(root_name, 0);

    try self.snapshot.init(abs_root, root_name, arena);
    try self.snapshot.insert(.{
        .id = self.next_entry_id.fetchAdd(1, .monotonic),
        .path = root_path,
    });

    try self.actions.putOne(self.io, .initial_scan);
    try self.waker.wake();
}

pub fn deinit(self: *Scanner) void {
    self.updates.close(self.io);
    self.jobs.close(self.io);
    self.actions.close(self.io);
    self.group.await(self.io) catch |err| {
        std.log.err("await err={}", .{err});
    };
    self.store.deinit(self.arena.allocator());
    if (self.workers) |workers| {
        for (workers) |*worker| {
            worker.deinit();
        }
    }

    var action_buf: [16]Action = undefined;
    while (true) {
        const n = self.actions.get(self.io, &action_buf, 0) catch break;
        if (n == 0) break;
        for (action_buf[0..n]) |action| {
            switch (action) {
                .entries => |entries| self.gpa.free(entries),
                else => {},
            }
        }
    }

    var buf: [8]Updates = undefined;
    while (true) {
        const n = self.updates.get(self.io, &buf, 0) catch break;
        if (n == 0) break;
        for (buf[0..n]) |update| {
            switch (update) {
                .updated => |u| {
                    var snap = u.snapshot;
                    snap.deinit(self.gpa);
                },
                else => {},
            }
        }
    }

    self.arena.deinit();
}

pub fn lock(self: *Scanner) !void {
    try self.mutex.lock(self.io);
}

pub fn unlock(self: *Scanner) void {
    self.mutex.unlock(self.io);
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
    var buffer: [16]Action = undefined;
    for (0..try self.actions.get(self.io, &buffer, 0)) |idx| {
        switch (buffer[idx]) {
            .initial_scan => try self.initialScan(waker),
            .entries => |entries| {
                for (entries) |entry| try self.snapshot.insert(entry);
                self.gpa.free(entries);
            },
            .initial_scan_end => {
                var copy = try self.snapshot.clone(self.gpa);
                errdefer copy.deinit(self.gpa);

                try self.updates.putOne(self.io, .{ .updated = .{
                    .snapshot = copy,
                    .scanning = false,
                } });
                try waker.wake();

                if (self.workers) |workers| {
                    for (workers) |*worker| {
                        worker.deinit();
                    }
                    self.workers = null;
                }
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

    _ = self.pending_jobs.fetchAdd(1, .monotonic);

    const root_entry = self.snapshot.entries.first() orelse return;

    try self.jobs.putOne(self.io, .{ .path_name = root_entry.path });

    const arena = self.arena.allocator();

    const cpu_count = try std.Thread.getCpuCount();
    self.workers = try arena.alloc(Worker, cpu_count);

    for (self.workers.?) |*worker| {
        worker.init(self, self.gpa);

        try self.group.concurrent(
            self.io,
            Worker.work,
            .{worker},
        );
    }
}

const ScannedChild = struct {
    path: ChunkedPath,
    is_dir: bool,
};

const Worker = struct {
    pub const Job = struct {
        path_name: ChunkedPath,
    };

    gpa: Allocator,
    scanner: *Scanner,
    queue: std.ArrayList(Job),
    entries: std.ArrayList(Snapshot.Entry),

    pub fn init(self: *Worker, scanner: *Scanner, gpa: Allocator) void {
        self.* = .{
            .gpa = gpa,
            .scanner = scanner,
            .queue = .empty,
            .entries = .empty,
        };
    }

    pub fn deinit(self: *Worker) void {
        self.queue.deinit(self.gpa);
        self.entries.deinit(self.gpa);
    }

    pub fn work(
        self: *Worker,
    ) void {
        self._work() catch |err| {
            if (err != error.Closed and err != error.Canceled) {
                std.log.err("worker err: {}", .{err});
            }
        };
    }

    pub fn _work(
        self: *Worker,
    ) !void {
        var jobs = &self.scanner.jobs;
        const io = self.scanner.io;

        var path_z: [MAX_PATH_LEN:0]u8 = undefined;

        while (true) {
            const job = if (self.queue.pop()) |job| job else try jobs.getOne(io);

            try self.scanDir(&path_z, job.path_name);

            try self.flushEntries();
            try self.flushLocalJobs(jobs);
            try self.finishJob();
            try self.scanner.waker.wake();
        }
    }

    fn scanDir(
        self: *Worker,
        path_z: [:0]u8,
        parent_path: ChunkedPath,
    ) !void {
        const abs_root = self.scanner.snapshot.abs_root;
        const root_name = self.scanner.snapshot.root_name;
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
            const store = &self.scanner.store;

            {
                try self.scanner.lock();
                defer self.scanner.unlock();

                path = store.append(parent_path, suffix, 1);
            }

            try self.entries.append(self.gpa, .{
                .path = path,
                .id = self.scanner.next_entry_id.fetchAdd(1, .monotonic),
            });

            if (entry.type != c.DT.DIR) continue;

            _ = self.scanner.pending_jobs.fetchAdd(1, .monotonic);
            try self.queue.append(self.gpa, .{
                .path_name = path,
            });
        }
    }

    fn flushEntries(self: *Worker) !void {
        if (self.entries.items.len == 0) return;

        var clone = try self.entries.clone(self.gpa);
        errdefer clone.deinit(self.gpa);
        try self.scanner.actions.putOne(self.scanner.io, .{ .entries = clone.items });

        self.entries.clearRetainingCapacity();
    }

    fn flushLocalJobs(self: *Worker, jobs: *Io.Queue(Job)) !void {
        while (self.queue.pop()) |qjob| {
            if (try jobs.put(self.scanner.io, &.{qjob}, 0) == 0) {
                self.queue.appendAssumeCapacity(qjob);
                break;
            }
        }
    }

    fn finishJob(self: *Worker) !void {
        const scanner = self.scanner;
        const pending = scanner.pending_jobs.fetchSub(1, .acq_rel);
        assert(pending > 0);

        if (pending != 1) return;

        scanner.jobs.close(scanner.io);
        try scanner.actions.putOne(self.scanner.io, .initial_scan_end);
    }
};

inline fn direntNameFromEntry(entry: *const c.dirent) []const u8 {
    const namlen: usize = @intCast(entry.namlen);
    return entry.name[0..namlen];
}
