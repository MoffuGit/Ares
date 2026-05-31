const std = @import("std");
const Io = std.Io;
const atomic = std.atomic;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const builtin = @import("builtin");

const ch = @import("../channel.zig");
const Snapshot = @import("snapshot.zig");

const UPDATE_INTERVAL: Io.Duration = if (builtin.mode == .Debug) .fromSeconds(5) else .fromMilliseconds(500);

const Scanner = @This();

pub const Updates = union(enum) {
    pub const Channel = ch.Channel(Updates);
    pub const Receiver = Channel.Receiver;
    pub const Sender = Channel.Sender;

    started: void,
    updated: struct {
        snapshot: Snapshot,
        scanning: bool,
    },
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

state: State,
gpa: Allocator,
arena: Allocator,
next_entry_id: *atomic.Value(u64),

pub fn init(self: *Scanner, gpa: Allocator, arena: Allocator, snapshot: *Snapshot, next_entry_id: *atomic.Value(u64)) !void {
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

pub fn run(self: *Scanner, io: Io, sender: *Updates.Sender) !void {
    assert(!(try sender.channel.closed(io)));
    assert(self.state.phase == .Initial);

    const stat = try Io.Dir.statFile(
        .cwd(),
        io,
        self.state.snapshot.abs_root,
        .{},
    );

    if (stat.kind != .directory) return;
    try sender.putOne(io, .started);

    try self.initial_scan(io, sender);
}

const Worker = struct {
    pub const Channel = ch.Channel(*Message);

    pub const Message = struct {
        buffer: [512]Worker.Job,
        len: u8,
    };

    pub const Job = struct {
        abs_path: []const u8,
        path_name: []const u8,
        sender: Channel.Sender,
    };

    const Pool = std.heap.MemoryPool(*Message);

    gpa: Allocator,
    arena: Allocator,
    pool: Pool,
    queue: std.SinglyLinkedList,

    pub fn work(self: *Worker, state: *State, io: Io, receiver: Channel.Receiver) void {
        var rec = receiver;
        defer rec.close(io);

        self._work(state, io, rec) catch |err| {
            std.log.err("worker err: {}", .{err});
        };

        self.pool.deinit(self.gpa);
    }

    pub fn _work(self: *Worker, state: *State, io: Io, receiver: Channel.Receiver) !void {
        var entries: std.ArrayList(Snapshot.Entry) = .empty;
        defer entries.deinit(self.gpa);

        var path_z: [4096:0]u8 = undefined;

        while (true) {
            const message: *Message = if (self.queue.popFirst()) |node|
                @ptrCast(@alignCast(node))
            else
                try receiver.getOne(io);

            defer self.pool.destroy(message);

            for (0..message.len) |idx| {
                const job = message.buffer[idx];
                defer job.sender.close(io);
            }
        }
    }
};

// fn scanDir(self: *Scanner, io: Io, path_z: [:0]u8, job: *ScanJob, entries: *std.ArrayList(Snapshot.Entry), jobs: *std.ArrayList(ScanJob)) !void {
//     assert(jobs.items.len == 0);
//
//     const abs_path = job.abs_path;
//     @memcpy(path_z[0..abs_path.len], abs_path);
//     path_z[abs_path.len] = 0;
//
//     const dir = c.opendir(path_z.ptr) orelse return posix.unexpectedErrno(posix.errno(-1));
//     defer _ = c.closedir(dir);
//
//     while (c.readdir(dir)) |entry_raw| {
//         const entry: *const c.dirent = @ptrCast(@alignCast(entry_raw));
//         const name = direntNameFromEntry(entry);
//         const is_dot = name.len == 1;
//         const is_dotdot = name.len == 2 and name[1] == '.';
//
//         if (is_dot or is_dotdot) continue;
//
//         const child_path = try std.mem.join(self.arena, "/", &.{ job.path_name, name });
//         const child_abs_path = try std.mem.join(self.arena, "/", &.{ job.abs_path, name });
//
//         try entries.append(self.gpa, .{ .path = child_path, .id = self.next_entry_id.fetchAdd(1, .monotonic) });
//
//         if (entry.type != c.DT.DIR) continue;
//
//         try jobs.append(self.gpa, .{
//             .abs_path = child_abs_path,
//             .path_name = child_path,
//             .sender = job.sender.clone(),
//         });
//     }
//
//     {
//         try self.state.mutex.lock(io);
//         defer self.state.mutex.unlock(io);
//         for (entries.items) |entry| try self.state.snapshot.insert(self.gpa, entry);
//     }
//
//     entries.clearRetainingCapacity();
//
//     if (jobs.items.len == 0) return;
//
//     const slice = try jobs.toOwnedSlice(self.gpa);
//     errdefer {
//         for (slice) |*new_job| {
//             new_job.sender.close(io);
//         }
//         self.gpa.free(slice);
//     }
//
//     try job.sender.putOne(io, .{ .batch = slice });
// }

pub fn initial_scan(self: *Scanner, io: Io, sender: *Updates.Sender) !void {
    const cpu_count = try std.Thread.getCpuCount();

    const buffer = try self.gpa.alloc(*Worker.Message, cpu_count * 10);
    defer self.gpa.free(buffer);

    var channel: Worker.Channel = .init(buffer);
    var group: Io.Group = .init;

    {
        const snapshot = self.state.snapshot;

        var _sender = channel.sender();
        errdefer _sender.close(io);

        const message = try self.arena.create(Worker.Message);
        errdefer self.arena.destroy(message);

        message.len = 1;
        message.buffer[0] = .{
            .job = .{
                .abs_path = snapshot.abs_root,
                .path_name = snapshot.root_name,
                .sender = _sender,
            },
        };

        try _sender.putOneUncancelable(
            io,
            message,
        );
    }

    for (0..cpu_count) |_| {
        const worker = try self.arena.create(Worker);
        errdefer self.arena.destroy(worker);

        worker.* = .{
            .arena = self.arena,
            .gpa = self.gpa,
            .pool = .empty,
        };

        const receiver = channel.receiver();
        try group.concurrent(io, Worker.work, .{ worker, &self.state, io, receiver });
    }

    const SelectResult = union(enum) {
        group: Io.Cancelable!void,
        timeout: Io.Cancelable!void,
    };
    const Select = Io.Select(SelectResult);

    var select_buffer: [2]SelectResult = undefined;

    var select: Select = .init(io, &select_buffer);

    try select.concurrent(.group, Io.Group.await, .{ &group, io });
    try select.concurrent(.timeout, Io.sleep, .{ io, UPDATE_INTERVAL, .real });

    while (true) {
        switch (try select.await()) {
            .group => {
                select.cancelDiscard();
                try self.send_update(io, false, sender);
                break;
            },
            .timeout => {
                try self.send_update(io, true, sender);
                try select.concurrent(.timeout, Io.sleep, .{ io, UPDATE_INTERVAL, .real });
            },
        }
    }
}

pub fn send_update(self: *Scanner, io: Io, scanning: bool, sender: *Updates.Sender) !void {
    var snapshot: Snapshot = undefined;
    {
        try self.state.lock(io);
        defer self.state.unlock(io);

        try snapshot.clone(&self.state.snapshot, self.gpa);
    }

    try sender.putOne(io, .{ .updated = .{ .snapshot = snapshot, .scanning = scanning } });
}
