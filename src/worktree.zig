const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Io = std.Io;
const channelpkg = @import("channel.zig");
const Channel = channelpkg.Channel;
const Scanner = @import("worktree/scanner.zig");
const Snapshot = @import("worktree/snapshot.zig");

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

buffer: [8]Scanner.ScanUpdates,
updates_channel: Channel(Scanner.ScanUpdates),
group: Io.Group,

pub fn init(self: *Worktree, gpa: Allocator, io: Io, opts: Options) !void {
    self.* = .{
        .scanning = false,
        .rwlock = .init,
        .arena = ArenaAllocator.init(gpa),
        .gpa = gpa,
        .group = .init,
        .snapshot = undefined,
        .scanner = undefined,
        .buffer = undefined,
        .updates_channel = undefined,
    };

    errdefer self.updates_channel.close(io);

    const arena = self.arena.allocator();
    errdefer _ = self.arena.reset(.free_all);

    const abs_root = try arena.dupe(u8, opts.abs_path);
    const basename = std.fs.path.basename(abs_root);
    const root_name = try arena.dupe(u8, basename);

    try self.snapshot.init(abs_root, root_name, gpa);
    errdefer self.snapshot.deinit(gpa);

    try self.scanner.init(arena, gpa, &self.snapshot);

    self.updates_channel = .init(&self.buffer);

    try self.group.concurrent(io, runUpdateReceiver, .{ self, io, self.updates_channel.receiver() });
    try self.group.concurrent(io, runScanner, .{ &self.scanner, io, self.updates_channel.sender() });
}

pub fn await(self: *Worktree, io: Io) !void {
    try self.group.await(io);
}

pub fn close(self: *Worktree, io: Io) !void {
    self.updates_channel.close(io);
}

pub fn deinit(self: *Worktree, io: Io) void {
    self.scanner.deinit(io);
    self.snapshot.deinit(self.gpa);
    _ = self.arena.reset(.free_all);
}

fn runUpdateReceiver(self: *Worktree, io: Io, receiver: channelpkg.ReceiverType(Scanner.ScanUpdates)) !void {
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

pub fn runScanner(scanner: *Scanner, io: Io, sender: channelpkg.SenderType(Scanner.ScanUpdates)) void {
    var send = sender;
    defer send.close(io);

    scanner.run(io, &send) catch |err| {
        std.log.err("scanner err: {}", .{err});
    };
}
