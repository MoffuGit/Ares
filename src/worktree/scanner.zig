const std = @import("std");
const Io = std.Io;
const c = std.c;
const atomic = std.atomic;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const heap = std.heap;
const builtin = @import("builtin");

const App = @import("../app.zig");
const sch = @import("../scheduler.zig");
const BackgroundScheduler = sch.BackgroundScheduler;
const Executor = BackgroundScheduler.Executor;
const Context = BackgroundScheduler.Context;
const Scheduler = sch.Scheduler;
const Snapshot = @import("snapshot.zig");
const tsk = @import("../tasks.zig");

const UPDATE_INTERVAL: Io.Duration = if (builtin.mode == .Debug) .fromSeconds(5) else .fromMilliseconds(100);

const Scanner = @This();
const max_path_len = 4096;

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
        },
    };
    const arena = self.arena.allocator();
    errdefer self.arena.deinit();

    self.jobs_buffer = try arena.alloc(Worker.Job, 1024);

    self.actions = .init(&self.action_buffer);
    self.updates = .init(&self.updates_buffer);
    self.jobs = .init(self.jobs_buffer);

    try self.state.snapshot.init(snapshot.abs_root, snapshot.root_name, arena);

    try self.state.snapshot.insert(.{
        .id = self.next_entry_id.fetchAdd(1, .monotonic),
        .path = snapshot.root_name,
    });

    try self.actions.putOne(self.io, .initial_scan);
    try self.waker.wake();
}

pub fn deinit(self: *Scanner) void {
    self.updates.close(self.io);
    self.jobs.close(self.io);
    self.actions.close(self.io);
    self.group.cancel(self.io);
    self.arena.deinit();
}

pub fn handleActions(
    self: *Scanner,
    ctx: Context,
    path_allocator: Allocator,
    waker: sch.Waker,
    res: anyerror!void,
) bool {
    res catch {
        self.deinit();
        return false;
    };
    self._handleActions(ctx, path_allocator, waker) catch {
        self.deinit();
        return false;
    };

    return true;
}

fn _handleActions(
    self: *Scanner,
    ctx: Context,
    path_allocator: Allocator,
    waker: sch.Waker,
) !void {
    var buffer: [8]Action = undefined;
    for (0..try self.actions.get(self.io, &buffer, 0)) |idx| {
        switch (buffer[idx]) {
            .initial_scan => try self.initialScan(ctx, path_allocator, waker),
            else => {},
        }
    }
}

fn initialScan(
    self: *Scanner,
    _: Context,
    path_allocator: Allocator,
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

    try self.jobs.putOne(self.io, .{
        .abs_path = self.state.snapshot.abs_root,
        .path_name = self.state.snapshot.root_name,
    });

    const cpu_count = try std.Thread.getCpuCount();
    for (0..cpu_count) |_| {
        const arena = self.arena.allocator();

        const worker = try arena.create(Worker);
        try worker.init(self, arena, waker);

        try self.group.concurrent(
            self.io,
            Worker.work,
            .{ worker, path_allocator },
        );
    }
}

const Worker = struct {
    pub const Job = struct {
        abs_path: []const u8,
        path_name: []const u8,
    };

    scanner: *Scanner,
    arena: Allocator,
    queue: std.ArrayList(Job),
    entries: std.ArrayList(Snapshot.Entry),
    waker: sch.Waker,

    pub fn init(self: *Worker, scanner: *Scanner, arena: Allocator, waker: sch.Waker) !void {
        const queue: std.ArrayList(Job) = .empty;
        const entries: std.ArrayList(Snapshot.Entry) = .empty;

        self.* = .{
            .arena = arena,
            .scanner = scanner,
            .queue = queue,
            .entries = entries,
            .waker = waker,
        };
    }

    pub fn work(
        self: *Worker,
        path_allocator: Allocator,
    ) void {
        self._work(path_allocator) catch |err| {
            if (err != error.Closed and err != error.Canceled) {
                std.log.err("worker err: {}", .{err});
            }
        };
    }

    pub fn _work(
        self: *Worker,
        path_allocator: Allocator,
    ) !void {
        var jobs = &self.scanner.jobs;
        const io = self.scanner.io;

        var path_z: [max_path_len:0]u8 = undefined;

        while (true) {
            const job = if (self.queue.pop()) |job| job else try jobs.getOne(io);

            try self.scanDir(&path_z, job.path_name, job.abs_path, path_allocator);

            try self.flushEntries();
            try self.flushLocalJobs(jobs);
            try self.finishJob();
        }
    }

    fn scanDir(
        self: *Worker,
        path_z: [:0]u8,
        path_name: []const u8,
        abs_path: []const u8,
        path_allocator: Allocator,
    ) !void {
        if (abs_path.len >= path_z.len) return error.NameTooLong;
        @memcpy(path_z[0..abs_path.len], abs_path);
        path_z[abs_path.len] = 0;

        const dir = c.opendir(path_z.ptr) orelse return;
        defer _ = c.closedir(dir);

        const point = ".";
        const pointpoint = "..";

        while (c.readdir(dir)) |entry_raw| {
            const entry: *const c.dirent = @ptrCast(@alignCast(entry_raw));
            const name = direntNameFromEntry(entry);

            if (std.mem.eql(u8, name, point) or std.mem.eql(u8, name, pointpoint)) continue;

            const child_path = try std.mem.join(path_allocator, "/", &.{ path_name, name });
            const child_abs_path = try std.mem.join(path_allocator, "/", &.{ abs_path, name });

            try self.entries.append(self.arena, .{
                .path = try self.arena.dupe(u8, child_path),
                .id = self.scanner.next_entry_id.fetchAdd(1, .monotonic),
            });

            if (entry.type != c.DT.DIR) continue;

            _ = self.scanner.pending_jobs.fetchAdd(1, .monotonic);
            try self.queue.append(self.arena, .{
                .abs_path = child_abs_path,
                .path_name = child_path,
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
