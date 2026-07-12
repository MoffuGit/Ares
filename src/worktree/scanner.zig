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
    temp: void,
};

const State = struct {
    const Self = @This();

    mutex: Io.Mutex,
    snapshot: Snapshot,
    store: ChunkedPathStore,

    pub fn lock(self: *Self, io: Io) Io.Cancelable!void {
        try self.mutex.lock(io);
    }

    pub fn unlock(self: *Self, io: Io) void {
        self.mutex.unlock(io);
    }
};

io: Io,
arena: heap.ArenaAllocator,
gpa: Allocator,
state: State,
action_buffer: [8]Action,
actions: Action.Queue,

updates_buffer: [8]Updates,
updates: Updates.Queue,

jobs_buffer: []Worker.Job,
jobs: Io.Queue(Worker.Job),

next_entry_id: atomic.Value(u64),
pending_jobs: atomic.Value(u64),

group: Io.Group,

waker: tsk.Waker,

pub fn init(
    self: *Scanner,
    waker: tsk.Waker,
    snapshot: *Snapshot,
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
        .state = .{
            .mutex = .init,
            .snapshot = undefined,
            .store = undefined,
        },
    };
    const arena = self.arena.allocator();
    errdefer self.arena.deinit();

    self.jobs_buffer = try arena.alloc(Worker.Job, 1024);

    self.actions = .init(&self.action_buffer);
    self.updates = .init(&self.updates_buffer);
    self.jobs = .init(self.jobs_buffer);

    try self.state.store.init(arena, .{ .chunk_capacity = 1024 * 1024, .inline_capacity = 1024 * 1024 });

    const root_path = self.state.store.put(snapshot.root_name, 0);

    try self.state.snapshot.init(snapshot.abs_root, snapshot.root_name, arena);

    try self.state.snapshot.insert(.{
        .id = self.next_entry_id.fetchAdd(1, .monotonic),
        .path = root_path,
    });

    try self.actions.putOne(self.io, .initial_scan);
    try self.waker.wake();
}

pub fn deinit(self: *Scanner) void {
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
    self.updates.close(self.io);
    self.jobs.close(self.io);
    self.actions.close(self.io);
    self.group.cancel(self.io);
    self.state.store.deinit(self.arena.allocator());
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
    var buffer: [8]Action = undefined;
    for (0..try self.actions.get(self.io, &buffer, 0)) |idx| {
        switch (buffer[idx]) {
            .initial_scan => try self.initialScan(ctx, waker),
            else => {},
        }
    }
}

fn initialScan(
    self: *Scanner,
    _: Context,
    waker: sch.Waker,
) !void {
    const stat = try Io.Dir.statFile(
        .cwd(),
        self.io,
        self.state.snapshot.abs_root,
        .{},
    );

    if (stat.kind != .directory) return;

    try self.updates.putOne(self.io, .started);
    try waker.wake();

    _ = self.pending_jobs.fetchAdd(1, .monotonic);

    const root_entry = self.state.snapshot.entries.first() orelse return;

    try self.jobs.putOne(self.io, .{
        .abs_path = self.state.snapshot.abs_root,
        .path_name = root_entry.path,
    });

    const cpu_count = try std.Thread.getCpuCount();
    for (0..cpu_count) |_| {
        const arena = self.arena.allocator();

        const worker = try arena.create(Worker);
        try worker.init(self, arena, waker);

        try self.group.concurrent(
            self.io,
            Worker.work,
            .{worker},
        );
    }
}

const ScannedChild = struct {
    name: []const u8,
    path: ChunkedPath,
    is_dir: bool,
};

const Worker = struct {
    pub const Job = struct {
        abs_path: []const u8,
        path_name: ChunkedPath,
    };

    scanner: *Scanner,
    arena: Allocator,
    queue: std.ArrayList(Job),
    entries: std.ArrayList(Snapshot.Entry),
    children: std.ArrayList(ScannedChild),
    waker: sch.Waker,

    pub fn init(self: *Worker, scanner: *Scanner, arena: Allocator, waker: sch.Waker) !void {
        const queue: std.ArrayList(Job) = .empty;
        const entries: std.ArrayList(Snapshot.Entry) = .empty;
        const children: std.ArrayList(ScannedChild) = .empty;

        self.* = .{
            .arena = arena,
            .scanner = scanner,
            .queue = queue,
            .entries = entries,
            .children = children,
            .waker = waker,
        };
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

            try self.scanDir(&path_z, job.path_name, job.abs_path);

            try self.flushEntries();
            try self.flushLocalJobs(jobs);
            try self.finishJob();
        }
    }

    fn scanDir(
        self: *Worker,
        path_z: [:0]u8,
        parent_path: ChunkedPath,
        abs_path: []const u8,
    ) !void {
        if (abs_path.len >= path_z.len) return error.NameTooLong;
        @memcpy(path_z[0..abs_path.len], abs_path);
        path_z[abs_path.len] = 0;

        const dir = c.opendir(path_z.ptr) orelse return;
        defer _ = c.closedir(dir);

        const point = ".";
        const pointpoint = "..";

        self.children.clearRetainingCapacity();

        while (c.readdir(dir)) |entry_raw| {
            const entry: *const c.dirent = @ptrCast(@alignCast(entry_raw));
            const name = direntNameFromEntry(entry);

            if (std.mem.eql(u8, name, point) or std.mem.eql(u8, name, pointpoint)) continue;

            const suffix_len: u32 = 1 + @as(u32, @intCast(name.len));
            const new_len = parent_path.len + suffix_len;
            if (new_len > MAX_PATH_LEN) continue;

            try self.children.append(self.arena, .{
                .name = try self.arena.dupe(u8, name),
                .path = undefined,
                .is_dir = entry.type == c.DT.DIR,
            });
        }

        {
            const io = self.scanner.io;
            try self.scanner.state.lock(io);
            defer self.scanner.state.unlock(io);

            const store = &self.scanner.state.store;

            for (self.children.items) |*child| {
                var suffix_buf: [MAX_PATH_LEN]u8 = undefined;
                suffix_buf[0] = '/';
                @memcpy(suffix_buf[1 .. 1 + child.name.len], child.name);
                const suffix = suffix_buf[0 .. 1 + child.name.len];

                child.path = store.append(parent_path, suffix, 1);

                try self.entries.append(self.arena, .{
                    .path = child.path,
                    .id = self.scanner.next_entry_id.fetchAdd(1, .monotonic),
                });
            }
        }

        for (self.children.items) |child| {
            if (!child.is_dir) continue;

            const child_abs_path = try std.mem.join(self.arena, "/", &.{ abs_path, child.name });

            _ = self.scanner.pending_jobs.fetchAdd(1, .monotonic);
            try self.queue.append(self.arena, .{
                .abs_path = child_abs_path,
                .path_name = child.path,
            });
        }
    }

    fn flushEntries(self: *Worker) !void {
        if (self.entries.items.len == 0) return;

        const io = self.scanner.io;
        try self.scanner.state.lock(io);
        defer self.scanner.state.unlock(io);

        for (self.entries.items) |entry| try self.scanner.state.snapshot.insert(entry);
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

        const io = scanner.io;
        try scanner.state.lock(io);
        defer scanner.state.unlock(io);

        var copy = try self.scanner.state.snapshot.clone(self.scanner.gpa);
        errdefer copy.deinit(self.scanner.gpa);

        try scanner.updates.putOne(io, .{ .updated = .{
            .snapshot = copy,
            .scanning = false,
        } });
        try self.waker.wake();
    }
};

inline fn direntNameFromEntry(entry: *const c.dirent) []const u8 {
    const namlen: usize = @intCast(entry.namlen);
    return entry.name[0..namlen];
}
