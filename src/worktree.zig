const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Io = std.Io;
const channelpkg = @import("channel.zig");
const Channel = channelpkg.Channel;
const Scanner = @import("worktree/scanner.zig");
const Snapshot = @import("worktree/snapshot.zig");
const prof = @import("prof");
const tripwire = prof.tripwire;
const test_build = @import("test_build");

pub const Worktree = @This();

pub const Options = struct {
    abs_path: []const u8,
};

arena: ArenaAllocator,
gpa: Allocator,

rwlock: Io.RwLock,
scanning: bool,
snapshot: Snapshot,
scanner: Scanner,

buffer: [8]Scanner.Updates,
updates_channel: Scanner.Updates.Channel,
group: Io.Group,
next_entry_id: std.atomic.Value(u64),

pub fn init(self: *Worktree, gpa: Allocator, opts: Options) !void {
    self.* = .{
        .scanning = false,
        .rwlock = .init,
        .arena = ArenaAllocator.init(gpa),
        .gpa = gpa,
        .group = .init,
        .snapshot = undefined,
        .scanner = undefined,
        .buffer = undefined,
        .next_entry_id = .init(0),
        .updates_channel = .init(&self.buffer),
    };

    const arena = self.arena.allocator();
    errdefer _ = self.arena.reset(.free_all);

    const abs_root = try arena.dupe(u8, opts.abs_path);
    const basename = std.fs.path.basename(abs_root);
    const root_name = try arena.dupe(u8, basename);

    try self.snapshot.init(abs_root, root_name, gpa);
    errdefer self.snapshot.deinit(gpa);
    try self.snapshot.insert(gpa, .{ .id = self.next_entry_id.fetchAdd(1, .monotonic), .path = root_name });

    try self.scanner.init(gpa, arena, &self.snapshot, &self.next_entry_id);
}

pub fn await(self: *Worktree, io: Io) !void {
    try self.group.await(io);
}

pub fn run(self: *Worktree, io: Io) !void {
    try self.group.concurrent(io, runUpdateReceiver, .{ self, io, self.updates_channel.receiver() });
    try self.group.concurrent(io, runScanner, .{ &self.scanner, io, self.updates_channel.sender() });
}

pub fn close(self: *Worktree, io: Io) !void {
    self.updates_channel.close(io);
}

pub fn deinit(self: *Worktree) void {
    self.scanner.deinit();
    self.snapshot.deinit(self.gpa);
    _ = self.arena.reset(.free_all);
}

fn runUpdateReceiver(self: *Worktree, io: Io, receiver: Scanner.Updates.Receiver) !void {
    var rec = receiver;
    defer rec.close(io);

    while (true) {
        switch (rec.getOne(io) catch return) {
            .started => {
                try self.rwlock.lock(io);
                defer self.rwlock.unlock(io);

                self.scanning = true;
            },
            .updated => |update| {
                try self.rwlock.lock(io);
                defer self.rwlock.unlock(io);

                self.snapshot.deinit(self.gpa);
                self.snapshot = update.snapshot;
                self.scanning = update.scanning;
            },
        }
    }
}

pub fn runScanner(scanner: *Scanner, io: Io, sender: Scanner.Updates.Sender) void {
    var send = sender;
    defer send.close(io);

    scanner.run(io, &send) catch |err| {
        if (err != error.Closed) {
            std.log.err("scanner err: {}", .{err});
        }
    };
}
