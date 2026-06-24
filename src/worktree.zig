const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Io = std.Io;
const atomic = std.atomic;
const path = std.fs.path;

const test_build = @import("test_build");

const App = @import("app.zig");
const Entity = App.Entity;
const Context = App.Context;
const channelpkg = @import("channel.zig");
const Channel = channelpkg.Channel;
const Scanner = @import("worktree/scanner.zig");
const Updates = Scanner.Updates;
const Snapshot = @import("worktree/snapshot.zig");

pub const Worktree = @This();

pub const Options = struct {
    abs_path: []const u8,
};

arena: Allocator,
gpa: Allocator,

scanning: bool,
snapshot: Snapshot,
scanner: Scanner,

buffer: [8]Updates,
channel: Updates.Channel,
next_entry_id: atomic.Value(u64),
handler: App.Handler,
io: Io,

pub fn init(self: *Worktree, ctx: Context(Worktree), io: Io, arena: Allocator, opts: Options) !void {
    self.* = .{
        .io = io,
        .gpa = ctx.gpa(),
        .arena = arena,
        .scanning = false,
        .snapshot = undefined,
        .scanner = undefined,
        .buffer = undefined,
        .next_entry_id = .init(0),
        .channel = .init(&self.buffer),
        .handler = undefined,
    };

    const abs_root = try arena.dupe(u8, opts.abs_path);
    const root_name = try arena.dupe(u8, path.basename(abs_root));

    try self.snapshot.init(abs_root, root_name, self.gpa);
    errdefer self.snapshot.deinit(self.gpa);

    try self.snapshot.insert(
        self.gpa,
        .{
            .id = self.next_entry_id.fetchAdd(1, .acq_rel),
            .path = root_name,
        },
    );

    try self.scanner.init(self.gpa, &self.snapshot, io);
    errdefer self.scanner.deinit(self.gpa);

    self.handler, const notifier = try ctx.await(flushUpdates, .{self.channel.receiver()});
    errdefer self.handler.drop();

    const executor = ctx.executor();

    executor.@"defer"(
        Scanner.run,
        .{
            &self.scanner,
            executor,
            self.channel.sender(),
            notifier,
            arena,
        },
    ).detach();
}

pub fn deinit(self: *Worktree) void {
    self.handler.drop();
    self.scanner.deinit(self.gpa);
    self.snapshot.deinit(self.gpa);
}

fn flushUpdates(ctx: Context(Worktree), receiver: Updates.Receiver, res: anyerror!void) bool {
    res catch return false;
    _flushUpdates(ctx, receiver) catch return false;

    return true;
}

fn _flushUpdates(ctx: Context(Worktree), receiver: Updates.Receiver) !void {
    var rec = receiver;

    const self, const update = ctx.update();
    defer update.end(self);

    var buffer: [8]Updates = undefined;
    for (0..try rec.get(self.io, &buffer, 0)) |idx| {
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
}

test "Worktree Entity" {
    const gpa = testing.allocator;
    const io = testing.io;

    var arena = ArenaAllocator.init(gpa);
    defer arena.deinit();

    var app: App = undefined;
    try app.init(gpa, io);
    defer app.deinit();

    const worktree: Entity(Worktree) = try .new(
        &app,
        .{
            io,
            arena.allocator(),
            Options{
                .abs_path = test_build.chromium_path,
            },
        },
    );

    worktree.drop();
    app.flush();
}
