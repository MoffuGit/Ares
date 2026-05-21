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
    sender: Channel.Sender,
};

buffer: [4 * 128 * 1024]ScanJob,

mutex: Io.Mutex,
state: State,
gpa: Allocator,
arena: Allocator,

abs_root: []u8,

pub fn init(self: *Scanner, arena: Allocator, gpa: Allocator, abs_root: []u8) !void {
    self.* = .{
        .arena = arena,
        .mutex = .init,
        .gpa = gpa,
        .buffer = undefined,
        .state = .{
            .phase = .Initial,
            .snapshot = undefined,
        },
        .abs_root = abs_root,
    };

    try self.state.snapshot.init(gpa);
}

pub fn run(self: *Scanner, io: Io) !void {
    assert(self.state.phase == .Initial);

    const root_stat = try Io.Dir.statFile(.cwd(), io, self.abs_root, .{});
    try self.insertEntry(io, self.abs_root);
    if (root_stat.kind != .directory) return;

    var channel: Channel = .init(&self.buffer);

    {
        var seed_sender = channel.sender();
        channel.queue.putOneUncancelable(io, .{
            .abs_path = self.abs_root,
            .sender = seed_sender,
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

    while (true) {
        var job = receiver.getOne(io) catch return;
        defer job.sender.close(io);

        self.scanDir(io, channel, job.abs_path) catch |err| {
            std.log.err("scan failed for {s}: {s}", .{ job.abs_path, @errorName(err) });
        };
    }
}

fn scanDir(self: *Scanner, io: Io, channel: *Channel, abs_path: []const u8) !void {
    var dir = try Io.Dir.openDirAbsolute(io, abs_path, .{ .iterate = true });
    defer dir.close(io);

    var collected: std.ArrayList([]const u8) = .empty;
    defer collected.deinit(self.gpa);

    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        const child_path = try std.fs.path.join(self.arena, &.{ abs_path, entry.name });

        try collected.append(self.gpa, child_path);

        if (entry.kind != .directory) continue;

        var child_sender = channel.sender();
        channel.queue.putOneUncancelable(io, .{
            .abs_path = child_path,
            .sender = child_sender,
        }) catch |err| switch (err) {
            error.Closed => {
                child_sender.close(io);
                return;
            },
        };
    }

    try self.insertEntries(io, collected.items);
}

fn insertEntries(self: *Scanner, io: Io, paths: []const []const u8) !void {
    try self.mutex.lock(io);
    defer self.mutex.unlock(io);
    for (paths) |path| try self.state.snapshot.insert(self.gpa, path);
}

fn insertEntry(self: *Scanner, io: Io, path: []const u8) !void {
    self.mutex.lockUncancelable(io);
    defer self.mutex.unlock(io);
    try self.state.snapshot.insert(self.gpa, path);
}
