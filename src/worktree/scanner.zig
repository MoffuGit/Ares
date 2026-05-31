const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const c = std.c;
const posix = std.posix;

const Snapshot = @import("snapshot.zig");

const channelpkg = @import("../channel.zig");
const Channel = channelpkg.Channel(Message);

const Scanner = @This();

const SNAPSHOT_UPDATE_INTERVAL: Io.Duration = if (@import("builtin").mode == .Debug) .fromSeconds(5) else .fromMilliseconds(500);

const State = struct {
    mutex: Io.Mutex,
    phase: Phase,
    snapshot: Snapshot,
};

const Phase = enum {
    Initial,
    Events,
};

pub const ScanUpdates = union(enum) {
    started: void,
    updated: struct {
        snapshot: Snapshot,
        scanning: bool,
    },
};

pub const ScanJob = struct {
    abs_path: []const u8,
    path_name: []const u8,
    sender: Channel.Sender,
};

const Message = union(enum) {
    batch: []ScanJob,
    job: ScanJob,
};

state: State,
gpa: Allocator,
arena: Allocator,
next_entry_id: *std.atomic.Value(u64),

pub fn init(self: *Scanner, arena: Allocator, gpa: Allocator, snapshot: *Snapshot, next_entry_id: *std.atomic.Value(u64)) !void {
    self.* = .{
        .arena = arena,
        .gpa = gpa,
        .next_entry_id = next_entry_id,
        .state = .{
            .mutex = .init,
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

    const buffer = try self.gpa.alloc(Message, 1024 * 128);
    defer self.gpa.free(buffer);
    var channel: Channel = .init(buffer);

    try update_sender.putOne(io, .started);

    {
        var sender = channel.sender();
        errdefer sender.close(io);

        try sender.putOneUncancelable(
            io,
            .{
                .job = .{
                    .abs_path = self.state.snapshot.abs_root,
                    .sender = sender,
                    .path_name = self.state.snapshot.root_name,
                },
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
                try self.send_update(io, false, update_sender);
                break;
            },
            .timeout => {
                try self.send_update(io, true, update_sender);
                try select.concurrent(.timeout, Io.sleep, .{ io, SNAPSHOT_UPDATE_INTERVAL, .real });
            },
        }
    }
}

pub fn send_update(self: *Scanner, io: Io, scanning: bool, update_sender: *channelpkg.SenderType(ScanUpdates)) !void {
    var snapshot: Snapshot = undefined;
    {
        try self.state.mutex.lock(io);
        defer self.state.mutex.unlock(io);

        try snapshot.clone(&self.state.snapshot, self.gpa);
    }

    try update_sender.putOne(io, .{ .updated = .{ .snapshot = snapshot, .scanning = scanning } });
}

pub fn deinit(self: *Scanner) void {
    self.state.snapshot.deinit(self.gpa);
}

fn scanTask(self: *Scanner, io: Io, receiver: Channel.Receiver) void {
    var rec = receiver;
    defer rec.close(io);

    var entries: std.ArrayList(Snapshot.Entry) = .empty;
    defer entries.deinit(self.gpa);

    var jobs: std.ArrayList(ScanJob) = .empty;
    defer jobs.deinit(self.gpa);

    var path_z: [4096:0]u8 = undefined;

    while (true) {
        var message = rec.getOne(io) catch return;

        switch (message) {
            .job => |*job| {
                defer job.sender.close(io);

                self.scanDir(io, &path_z, job, &entries, &jobs) catch |err| {
                    std.log.err("scan failed for {s}: {s}", .{ job.abs_path, @errorName(err) });
                    break;
                };
            },
            .batch => |batch| {
                defer self.gpa.free(batch);

                for (batch) |*job| {
                    defer job.sender.close(io);

                    self.scanDir(io, &path_z, job, &entries, &jobs) catch |err| {
                        std.log.err("scan failed for {s}: {s}", .{ job.abs_path, @errorName(err) });
                        break;
                    };
                }
            },
        }
    }
}

fn scanDir(self: *Scanner, io: Io, path_z: [:0]u8, job: *ScanJob, entries: *std.ArrayList(Snapshot.Entry), jobs: *std.ArrayList(ScanJob)) !void {
    assert(jobs.items.len == 0);

    const abs_path = job.abs_path;
    @memcpy(path_z[0..abs_path.len], abs_path);
    path_z[abs_path.len] = 0;

    const dir = c.opendir(path_z.ptr) orelse return posix.unexpectedErrno(posix.errno(-1));
    defer _ = c.closedir(dir);

    while (c.readdir(dir)) |entry_raw| {
        const entry: *const c.dirent = @ptrCast(@alignCast(entry_raw));
        const name = direntNameFromEntry(entry);
        const is_dot = name.len == 1;
        const is_dotdot = name.len == 2 and name[1] == '.';

        if (is_dot or is_dotdot) continue;

        const child_path = try std.mem.join(self.arena, "/", &.{ job.path_name, name });
        const child_abs_path = try std.mem.join(self.arena, "/", &.{ job.abs_path, name });

        try entries.append(self.gpa, .{ .path = child_path, .id = self.next_entry_id.fetchAdd(1, .monotonic) });

        if (entry.type != c.DT.DIR) continue;

        try jobs.append(self.gpa, .{
            .abs_path = child_abs_path,
            .path_name = child_path,
            .sender = job.sender.clone(),
        });
    }

    {
        try self.state.mutex.lock(io);
        defer self.state.mutex.unlock(io);
        for (entries.items) |entry| try self.state.snapshot.insert(self.gpa, entry);
    }

    entries.clearRetainingCapacity();

    if (jobs.items.len == 0) return;

    const slice = try jobs.toOwnedSlice(self.gpa);
    errdefer {
        for (slice) |*new_job| {
            new_job.sender.close(io);
        }
        self.gpa.free(slice);
    }

    try job.sender.putOne(io, .{ .batch = slice });
}

inline fn direntNameFromEntry(entry: *const c.dirent) []const u8 {
    const namlen: usize = @intCast(entry.namlen);
    return entry.name[0..namlen];
}
