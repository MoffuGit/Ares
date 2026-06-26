const std = @import("std");
const Io = std.Io;
const c = std.c;
const atomic = std.atomic;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const heap = std.heap;
const builtin = @import("builtin");

const App = @import("../app.zig");
const Executor = App.Executor;
const ch = @import("../channel.zig");
const Snapshot = @import("snapshot.zig");

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
gpa: Allocator,
state: State,
action_buffer: [8]Action,
actions: Action.Queue,

updates_buffer: [8]Updates,
updates: Updates.Queue,

jobs_buffer: [1024]Worker.Job,
jobs: Io.Queue(Worker.Job),

next_entry_id: atomic.Value(u64),
pending_jobs: atomic.Value(u64),

pub fn init(
    self: *Scanner,
    arena: Allocator,
    snapshot: *Snapshot,
    gpa: Allocator,
    io: Io,
) !void {
    self.* = .{
        .io = io,
        .gpa = gpa,
        .action_buffer = undefined,
        .updates_buffer = undefined,
        .jobs_buffer = undefined,
        .actions = .init(&self.action_buffer),
        .updates = .init(&self.updates_buffer),
        .jobs = .init(&self.jobs_buffer),
        .next_entry_id = .init(0),
        .pending_jobs = .init(0),
        .state = .{
            .mutex = .init,
            .snapshot = undefined,
        },
    };

    try self.state.snapshot.clone(snapshot, arena);

    try self.state.snapshot.insert(arena, .{
        .id = self.next_entry_id.fetchAdd(1, .monotonic),
        .path = snapshot.root_name,
    });
}

pub fn handleActions(
    self: *Scanner,
    arena: Allocator,
    waker: App.Waker,
    group: *App.Group,
    res: anyerror!void,
) bool {
    res catch return false;
    self._handleActions(arena, waker, group) catch return false;

    return true;
}

pub fn stop(self: *Scanner) void {
    self.updates.close(self.io);
    self.jobs.close(self.io);
    self.actions.close(self.io);
}

fn _handleActions(
    self: *Scanner,
    arena: Allocator,
    waker: App.Waker,
    group: *App.Group,
) !void {
    var buffer: [8]Action = undefined;
    for (0..try self.actions.get(self.io, &buffer, 0)) |idx| {
        switch (buffer[idx]) {
            .initial_scan => try self.initialScan(arena, waker, group),
            else => {},
        }
    }
}

fn initialScan(
    self: *Scanner,
    arena: Allocator,
    waker: App.Waker,
    group: *App.Group,
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
        const worker = try group.arena().create(Worker);
        try worker.init(self, arena, group, waker);

        group.concurrent(
            Worker.work,
            .{worker},
        );
    }
}

const Worker = struct {
    pub const Channel = ch.Channel(Job);

    pub const Job = struct {
        abs_path: []const u8,
        path_name: []const u8,
    };

    scanner: *Scanner,
    arena: Allocator,
    group: *App.Group,
    queue: std.ArrayList(Job),
    entries: std.ArrayList(Snapshot.Entry),
    waker: App.Waker,

    pub fn init(self: *Worker, scanner: *Scanner, arena: Allocator, group: *App.Group, waker: App.Waker) !void {
        const queue: std.ArrayList(Job) = try .initCapacity(group.arena(), 400);
        const entries: std.ArrayList(Snapshot.Entry) = try .initCapacity(group.arena(), 800);

        self.* = .{
            .arena = arena,
            .scanner = scanner,
            .group = group,
            .queue = queue,
            .entries = entries,
            .waker = waker,
        };
    }

    pub fn work(
        self: *Worker,
        _: *App.Group,
    ) bool {
        self._work() catch |err| {
            if (err != error.Closed and err != error.Canceled) {
                std.log.err("worker err: {}", .{err});
            }
        };

        return false;
    }

    pub fn _work(self: *Worker) !void {
        var jobs = &self.scanner.jobs;
        const io = self.scanner.io;

        var path_z: [max_path_len:0]u8 = undefined;

        while (true) {
            const job = if (self.queue.pop()) |job| job else try jobs.getOne(io);

            try self.scanDir(&path_z, job.path_name, job.abs_path);

            try self.flushEntries();
            try self.flushLocalJobs(jobs);
            try self.finishJob();
        }
    }

    fn scanDir(self: *Worker, path_z: [:0]u8, path_name: []const u8, abs_path: []const u8) !void {
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

            const child_path = try std.mem.join(self.arena, "/", &.{ path_name, name });
            const child_abs_path = try std.mem.join(self.arena, "/", &.{ abs_path, name });

            try self.entries.append(self.group.arena(), .{
                .path = try self.group.arena().dupe(u8, child_path),
                .id = self.scanner.next_entry_id.fetchAdd(1, .monotonic),
            });

            if (entry.type != c.DT.DIR) continue;

            _ = self.scanner.pending_jobs.fetchAdd(1, .monotonic);
            try self.queue.append(self.group.arena(), .{
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

        for (self.entries.items) |entry| try self.scanner.state.snapshot.insert(self.group.arena(), entry);
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

        var snapshot: Snapshot = undefined;
        try snapshot.clone(&scanner.state.snapshot, self.scanner.gpa);
        errdefer snapshot.deinit(self.scanner.gpa);

        try scanner.updates.putOne(io, .{ .updated = .{
            .snapshot = snapshot,
            .scanning = false,
        } });
        try self.waker.wake();
    }
};

inline fn direntNameFromEntry(entry: *const c.dirent) []const u8 {
    const namlen: usize = @intCast(entry.namlen);
    return entry.name[0..namlen];
}
