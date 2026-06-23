const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Io = std.Io;

const prof = @import("prof");
const tripwire = prof.tripwire;
const test_build = @import("test_build");

const App = @import("app.zig");
const Entity = App.Entity;
const Context = App.Context;
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

scanning: bool,
snapshot: Snapshot,
scanner: Scanner,

buffer: [8]Scanner.Updates,
updates_channel: Scanner.Updates.Channel,
next_entry_id: std.atomic.Value(u64),
handlers: [1]App.Handler,

pub fn init(self: *Worktree, ctx: Context(Worktree), gpa: Allocator, opts: Options, io: Io) !void {
    self.* = .{
        .scanning = false,
        .arena = ArenaAllocator.init(gpa),
        .gpa = gpa,
        .snapshot = undefined,
        .scanner = undefined,
        .buffer = undefined,
        .next_entry_id = .init(0),
        .updates_channel = .init(&self.buffer),
        .handlers = undefined,
    };

    const arena = self.arena.allocator();
    errdefer _ = self.arena.deinit();

    const abs_root = try arena.dupe(u8, opts.abs_path);
    const basename = std.fs.path.basename(abs_root);
    const root_name = try arena.dupe(u8, basename);

    try self.snapshot.init(abs_root, root_name, gpa);
    errdefer self.snapshot.deinit(gpa);
    try self.snapshot.insert(gpa, .{ .id = self.next_entry_id.fetchAdd(1, .monotonic), .path = root_name });

    const handler, const notifier = try ctx.async(awaitUpdates, .{ io, self.updates_channel.receiver() });
    errdefer handler.drop();

    self.handlers = .{handler};

    try self.scanner.init(gpa, arena, &self.snapshot, &self.next_entry_id);
    errdefer self.scanner.deinit();

    const bg_handler, const bg_notifier = try ctx.backgroundAsync(
        Scanner.run,
        .{ &self.scanner, io, self.updates_channel.sender(), notifier },
    );
    bg_handler.detach();

    try bg_notifier.notify();
}

pub fn close(self: *Worktree, io: Io) !void {
    self.updates_channel.close(io);
}

pub fn deinit(self: *Worktree) void {
    for (self.handlers) |handler| {
        handler.drop();
    }
    self.scanner.deinit();
    self.snapshot.deinit(self.gpa);
    self.arena.deinit();
}

fn awaitUpdates(ctx: Context(Worktree), io: Io, receiver: Scanner.Updates.Receiver, res: anyerror!void) bool {
    if (res == error.Canceled) {
        return false;
    }

    var rec = receiver;

    const self, const update = ctx.update();
    defer update.end(self);

    var buffer: [8]Scanner.Updates = undefined;
    for (0..rec.get(io, &buffer, 0) catch return false) |idx| {
        switch (buffer[idx]) {
            .started => self.scanning = true,
            .updated => |updated| {
                self.snapshot.deinit(self.gpa);
                self.snapshot = updated.snapshot;
                self.scanning = updated.scanning;
            },
        }
    }

    ctx.notify();

    return true;
}
