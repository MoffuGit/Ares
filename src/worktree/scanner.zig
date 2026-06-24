const std = @import("std");
const Io = std.Io;
const c = std.c;
const atomic = std.atomic;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const heap = std.heap;
const builtin = @import("builtin");

const App = @import("../app.zig");
const Executor = App.BackgroundExecutor;
const ch = @import("../channel.zig");
const Snapshot = @import("snapshot.zig");

const UPDATE_INTERVAL: Io.Duration = if (builtin.mode == .Debug) .fromSeconds(5) else .fromMilliseconds(100);

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
group: App.Group,
io: Io,

pub fn init(
    self: *Scanner,
    gpa: Allocator,
    snapshot: *const Snapshot,
    io: Io,
) !void {
    self.* = .{
        .group = .init,
        .io = io,
        .state = .{
            .mutex = .init,
            .snapshot = undefined,
        },
    };

    try self.state.snapshot.clone(snapshot, gpa);
}

pub fn deinit(self: *Scanner, gpa: Allocator) void {
    self.state.snapshot.deinit(gpa);
    self.group.drop(self.io);
}

pub fn run(
    self: *Scanner,
    executor: *Executor,
    sender: Updates.Sender,
    notifier: App.Notifier,
    arena: Allocator,
) bool {
    self._run(executor, @constCast(&sender), notifier, arena) catch {};

    return false;
}

pub fn _run(
    self: *Scanner,
    _: *Executor,
    sender: *Updates.Sender,
    notifier: App.Notifier,
    _: Allocator,
) !void {
    const stat = try Io.Dir.statFile(
        .cwd(),
        self.io,
        self.state.snapshot.abs_root,
        .{},
    );

    if (stat.kind != .directory) return;
    try sender.putOne(self.io, .started);
    try notifier.notify();
    //
    // try self.initial_scan(io, &sender, notifier);
}
//
//
// pub fn initial_scan(self: *Scanner, io: Io, sender: *Updates.Sender, notifier: App.Notifier) !void {
//     // const cpu_count = try std.Thread.getCpuCount();
//     //
//     // var buffer: [1024]Worker.Job = undefined;
//     //
//     // var channel: Worker.Channel = .init(&buffer);
//     // var group: Io.Group = .init;
//     // {
//     //     const snapshot = self.state.snapshot;
//     //
//     //     var _sender = channel.sender();
//     //     errdefer _sender.close(io);
//     //
//     //     try _sender.putOneUncancelable(
//     //         io,
//     //         .{
//     //             .abs_path = snapshot.abs_root,
//     //             .path_name = snapshot.root_name,
//     //             .sender = _sender,
//     //         },
//     //     );
//     // }
//     //
//     // for (0..cpu_count) |_| {
//     //     const worker = try self.arena.create(Worker);
//     //     errdefer self.arena.destroy(worker);
//     //
//     //     try worker.init(self.gpa, self.arena, self.next_entry_id);
//     //
//     //     const receiver = channel.receiver();
//     //     try group.concurrent(io, Worker.work, .{ worker, &self.state, io, receiver });
//     // }
//     //
//     // const SelectResult = union(enum) {
//     //     group: Io.Cancelable!void,
//     //     timeout: Io.Cancelable!void,
//     // };
//     // const Select = Io.Select(SelectResult);
//     //
//     // var select_buffer: [2]SelectResult = undefined;
//     //
//     // var select: Select = .init(io, &select_buffer);
//     //
//     // try select.concurrent(.group, Io.Group.await, .{ &group, io });
//     // try select.concurrent(.timeout, Io.sleep, .{ io, UPDATE_INTERVAL, .real });
//     try io.sleep(.fromSeconds(1), .real);
//
//     try self.send_update(io, false, sender, notifier);
//     // while (true) {
//     //     switch (try select.await()) {
//     //         .group => {
//     //             select.cancelDiscard();
//     //             try self.send_update(io, false, sender, notifier);
//     //             break;
//     //         },
//     //         .timeout => {
//     //             try self.send_update(io, true, sender, notifier);
//     //             try select.concurrent(.timeout, Io.sleep, .{ io, UPDATE_INTERVAL, .real });
//     //         },
//     //     }
//     // }
// }
//
// pub fn send_update(self: *Scanner, io: Io, scanning: bool, sender: *Updates.Sender, notifier: App.Notifier) !void {
//     var snapshot: Snapshot = undefined;
//     {
//         try self.state.lock(io);
//         defer self.state.unlock(io);
//
//         try snapshot.clone(&self.state.snapshot, self.gpa);
//     }
//
//     try sender.putOne(io, .{ .updated = .{ .snapshot = snapshot, .scanning = scanning } });
//
//     try notifier.notify();
// }

const Worker = struct {
    pub const Channel = ch.Channel(Job);

    pub const Job = struct {
        abs_path: []const u8,
        path_name: []const u8,
        sender: Channel.Sender,
    };

    gpa: Allocator,
    arena: Allocator,
    // queue: std.ArrayList(Job),
    // entries: std.ArrayList(Snapshot.Entry),
    // next_entry_id: *atomic.Value(u64),

    pub fn init(self: *Worker, gpa: Allocator, arena: Allocator) !void {
        // const queue: std.ArrayList(Job) = try .initCapacity(gpa, 400);
        // const entries: std.ArrayList(Snapshot.Entry) = try .initCapacity(gpa, 800);

        self.* = .{
            .arena = arena,
            .gpa = gpa,
            // .queue = queue,
            // .entries = entries,
            // .next_entry_id = next_entry_id,
        };
    }

    pub fn deinit(_: *Worker) void {
        // self.queue.deinit(self.gpa);
        // self.entries.deinit(self.gpa);
    }
    //
    // pub fn work(self: *Worker, state: *State, io: Io, receiver: Channel.Receiver) void {
    //     var rec = receiver;
    //     defer rec.close(io);
    //     defer self.queue.deinit(self.gpa);
    //     defer self.entries.deinit(self.gpa);
    //
    //     self._work(state, io, rec) catch |err| {
    //         if (err != error.Closed) {
    //             std.log.err("worker err: {}", .{err});
    //         }
    //     };
    // }
    //
    // pub fn _work(self: *Worker, state: *State, io: Io, receiver: Channel.Receiver) !void {
    //     var rec = receiver;
    //     var path_z: [4096:0]u8 = undefined;
    //     while (true) {
    //         var job = if (self.queue.pop()) |job| job else try rec.getOne(io);
    //         defer job.sender.close(io);
    //
    //         try self.scanDir(&path_z, job.path_name, job.abs_path, &job.sender);
    //
    //         {
    //             try state.lock(io);
    //             defer state.unlock(io);
    //
    //             for (self.entries.items) |entry| try state.snapshot.insert(self.gpa, entry);
    //             self.entries.clearRetainingCapacity();
    //         }
    //
    //         while (self.queue.pop()) |qjob| {
    //             if (try @constCast(&job.sender).put(io, &.{qjob}, 0) == 0) {
    //                 try self.queue.append(self.gpa, qjob);
    //                 break;
    //             }
    //         }
    //     }
    // }
    //
    // fn scanDir(self: *Worker, path_z: [:0]u8, path_name: []const u8, abs_path: []const u8, sender: *Channel.Sender) !void {
    //     @memcpy(path_z[0..abs_path.len], abs_path);
    //     path_z[abs_path.len] = 0;
    //
    //     const dir = c.opendir(path_z.ptr) orelse return error.OPENDIR;
    //     defer _ = c.closedir(dir);
    //
    //     const point = ".";
    //     const pointpoint = "..";
    //
    //     while (c.readdir(dir)) |entry_raw| {
    //         const entry: *const c.dirent = @ptrCast(@alignCast(entry_raw));
    //         const name = direntNameFromEntry(entry);
    //
    //         if (std.mem.eql(u8, name, point) or std.mem.eql(u8, name, pointpoint)) continue;
    //
    //         const child_path = try std.mem.join(self.arena, "/", &.{ path_name, name });
    //         const child_abs_path = try std.mem.join(self.arena, "/", &.{ abs_path, name });
    //
    //         try self.entries.append(self.gpa, .{ .path = child_path, .id = self.next_entry_id.fetchAdd(1, .monotonic) });
    //
    //         if (entry.type != c.DT.DIR) continue;
    //
    //         try self.queue.append(self.gpa, .{
    //             .abs_path = child_abs_path,
    //             .path_name = child_path,
    //             .sender = sender.clone(),
    //         });
    //     }
    // }
};
