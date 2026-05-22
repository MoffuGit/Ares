const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Snapshot = @import("snapshot.zig");

const Channel = @import("../channel.zig").Channel(ScanJob);

const Scanner = @This();

const State = struct {
    phase: Phase,
    snapshot: Snapshot,
};

const Phase = enum {
    Initial,
    Events,
};

pub const ScanJob = struct {
    abs_path: []u8,
    path_name: []u8,
    sender: Channel.Sender,
};

buffer: [256 * 256]ScanJob,

mutex: Io.Mutex,
state: State,
gpa: Allocator,
arena: Allocator,

pub fn init(self: *Scanner, arena: Allocator, gpa: Allocator, abs_root: []u8, root_name: []u8) !void {
    self.* = .{
        .arena = arena,
        .mutex = .init,
        .gpa = gpa,
        .buffer = undefined,
        .state = .{
            .phase = .Initial,
            .snapshot = undefined,
        },
    };

    try self.state.snapshot.init(abs_root, root_name, gpa);
}

pub fn run(self: *Scanner, io: Io) !void {
    assert(self.state.phase == .Initial);

    try self.state.snapshot.insert(self.gpa, self.state.snapshot.root_name);

    const root_stat = try Io.Dir.statFile(.cwd(), io, self.state.snapshot.abs_root, .{});

    if (root_stat.kind != .directory) return;

    var channel: Channel = .init(&self.buffer);

    {
        var seed_sender = channel.sender();
        channel.queue.putOneUncancelable(io, .{
            .abs_path = self.state.snapshot.abs_root,
            .sender = seed_sender,
            .path_name = self.state.snapshot.root_name,
        }) catch |err| switch (err) {
            error.Closed => {
                seed_sender.close(io);
                return;
            },
        };
    }

    const cpu_count = try std.Thread.getCpuCount();

    var group: Io.Group = .init;
    for (0..cpu_count) |_| {
        const receiver = channel.receiver();
        try group.concurrent(io, scanTask, .{ self, io, &channel, receiver });
    }

    try group.await(io);
}

pub fn deinit(self: *Scanner, _: Io) void {
    self.state.snapshot.deinit(self.gpa);
}

fn scanTask(self: *Scanner, io: Io, channel: *Channel, receiver_in: Channel.Receiver) void {
    var receiver = receiver_in;
    defer receiver.close(io);

    var entries: std.ArrayList([]const u8) = .empty;
    defer entries.deinit(self.gpa);

    var jobs: std.ArrayList(ScanJob) = .empty;
    defer jobs.deinit(self.gpa);

    while (true) {
        var job = receiver.getOne(io) catch return;
        defer job.sender.close(io);

        self.scanDir(io, channel, &job, &entries, &jobs) catch |err| {
            std.log.err("scan failed for {s}: {s}", .{ job.abs_path, @errorName(err) });
        };
    }
}

fn scanDir(self: *Scanner, io: Io, channel: *Channel, job: *ScanJob, entries: *std.ArrayList([]const u8), jobs: *std.ArrayList(ScanJob)) !void {
    var dir = try Io.Dir.openDirAbsolute(io, job.abs_path, .{ .iterate = true });
    defer dir.close(io);

    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        const child_path = try std.fs.path.join(self.arena, &.{ job.path_name, entry.name });
        const child_abs_path = try std.fs.path.join(self.arena, &.{ job.abs_path, entry.name });
        try entries.append(self.gpa, child_path);

        if (entry.kind != .directory) continue;

        try jobs.append(self.gpa, .{
            .abs_path = child_abs_path,
            .path_name = child_path,
            .sender = channel.sender(),
        });
    }

    {
        try self.mutex.lock(io);
        defer self.mutex.unlock(io);
        for (entries.items) |path| try self.state.snapshot.insert(self.gpa, path);
    }

    entries.clearRetainingCapacity();

    if (jobs.items.len > 0) {
        channel.queue.putAll(io, jobs.items) catch {
            for (jobs.items) |*new_job| new_job.sender.close(io);
        };
        jobs.clearRetainingCapacity();
    }
}
