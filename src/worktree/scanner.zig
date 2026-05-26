const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Snapshot = @import("snapshot.zig");

const channelpkg = @import("../channel.zig");
const Channel = channelpkg.Channel(ScanJob);

const Scanner = @This();

const SNAPSHOT_UPDATE_INTERVAL: Io.Duration = if (@import("builtin").mode == .Debug) .fromSeconds(5) else .fromMilliseconds(500);

const State = struct {
    phase: Phase,
    snapshot: Snapshot,
};

const Phase = enum {
    Initial,
    Events,
};

pub const ScanUpdates = union(enum) {
    started: void,
    updated: Snapshot,
};

pub const ScanJob = struct {
    abs_path: []const u8,
    path_name: []const u8,
    sender: Channel.Sender,
};

buffer: [256 * 256]ScanJob,

mutex: Io.Mutex,
state: State,
gpa: Allocator,
arena: Allocator,

pub fn init(self: *Scanner, arena: Allocator, gpa: Allocator, snapshot: *Snapshot) !void {
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

    try self.state.snapshot.clone(snapshot, gpa);
}

pub fn run(self: *Scanner, io: Io, update_sender: *channelpkg.SenderType(ScanUpdates)) !void {
    assert(try update_sender.channel.closed(io) != true);
    assert(self.state.phase == .Initial);

    const stat = try Io.Dir.statFile(.cwd(), io, self.state.snapshot.abs_root, .{});
    if (stat.kind != .directory) return;

    var channel: Channel = .init(&self.buffer);

    try update_sender.putOne(io, .started);

    {
        var sender = channel.sender();
        errdefer sender.close(io);

        try sender.putOneUncancelable(
            io,
            .{
                .abs_path = self.state.snapshot.abs_root,
                .sender = sender,
                .path_name = self.state.snapshot.root_name,
            },
        );
    }

    const cpu_count = try std.Thread.getCpuCount();

    var group: Io.Group = .init;
    for (0..cpu_count) |_| {
        const receiver = channel.receiver();
        try group.concurrent(io, scanTask, .{ self, io, receiver });
    }

    const SelectResult = union(enum) {
        group: Io.Cancelable!void,
        timeout: Io.Cancelable!void,
    };
    const Select = Io.Select(SelectResult);

    var select_buffer: [2]SelectResult = undefined;

    var select: Select = .init(io, &select_buffer);

    try select.concurrent(.group, Io.Group.await, .{ &group, io });
    try select.concurrent(.timeout, Io.sleep, .{ io, SNAPSHOT_UPDATE_INTERVAL, .real });

    while (true) {
        switch (try select.await()) {
            .group => {
                select.cancelDiscard();
                break;
            },
            .timeout => {
                var snapshot: Snapshot = undefined;
                {
                    try self.mutex.lock(io);
                    defer self.mutex.unlock(io);

                    try snapshot.clone(&self.state.snapshot, self.gpa);
                }

                try update_sender.putOne(io, .{ .updated = snapshot });
                try select.concurrent(.timeout, Io.sleep, .{ io, SNAPSHOT_UPDATE_INTERVAL, .real });
            },
        }
    }
}

pub fn deinit(self: *Scanner, _: Io) void {
    self.state.snapshot.deinit(self.gpa);
}

fn scanTask(self: *Scanner, io: Io, receiver: Channel.Receiver) void {
    var rec = receiver;
    defer rec.close(io);

    var entries: std.ArrayList([]const u8) = .empty;
    defer entries.deinit(self.gpa);

    var jobs: std.ArrayList(ScanJob) = .empty;
    defer jobs.deinit(self.gpa);

    while (true) {
        var job = rec.getOne(io) catch return;
        defer job.sender.close(io);

        self.scanDir(io, &job, &entries, &jobs) catch |err| {
            std.log.err("scan failed for {s}: {s}", .{ job.abs_path, @errorName(err) });
            break;
        };
    }
}

fn scanDir(self: *Scanner, io: Io, job: *ScanJob, entries: *std.ArrayList([]const u8), jobs: *std.ArrayList(ScanJob)) !void {
    var dir = try Io.Dir.openDirAbsolute(io, job.abs_path, .{ .iterate = true });
    defer dir.close(io);

    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        const child_path = try std.mem.join(self.arena, "/", &.{ job.path_name, entry.name });
        const child_abs_path = try std.mem.join(self.arena, "/", &.{ job.abs_path, entry.name });
        try entries.append(self.gpa, child_path);

        if (entry.kind != .directory) continue;

        try jobs.append(self.gpa, .{
            .abs_path = child_abs_path,
            .path_name = child_path,
            .sender = job.sender.clone(),
        });
    }

    {
        try self.mutex.lock(io);
        defer self.mutex.unlock(io);
        for (entries.items) |path| try self.state.snapshot.insert(self.gpa, path);
    }

    entries.clearRetainingCapacity();

    if (jobs.items.len > 0) {
        job.sender.putAll(io, jobs.items) catch {
            for (jobs.items) |*new_job| new_job.sender.close(io);
        };
        jobs.clearRetainingCapacity();
    }
}
