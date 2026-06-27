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
const Scanner = @import("worktree/scanner.zig");
const Updates = Scanner.Updates;
const Snapshot = @import("worktree/snapshot.zig");

pub const Worktree = @This();

pub const Options = struct {
    abs_path: []const u8,
};

gpa: Allocator,
scanning: bool,
snapshot: Snapshot,
handler: App.Handler,
group: *App.Group,
waker: App.Waker,
io: Io,
scanner: *Scanner,

pub fn init(self: *Worktree, ctx: Context(Worktree), io: Io, arena: Allocator, opts: Options) !void {
    self.* = .{
        .io = io,
        .gpa = ctx.gpa(),
        .scanning = false,
        .snapshot = undefined,
        .handler = undefined,
        .group = ctx.executor().group(),
        .scanner = undefined,
        .waker = undefined,
    };

    errdefer self.group.close();

    const abs_root = try arena.dupe(u8, opts.abs_path);
    const root_name = try arena.dupe(u8, path.basename(abs_root));

    try self.snapshot.init(abs_root, root_name, self.gpa);
    errdefer self.snapshot.deinit(self.gpa);

    const scanner = try self.group.arena().create(Scanner);
    try scanner.init(self.group.arena(), &self.snapshot, self.gpa, io);
    self.scanner = scanner;

    self.handler, const waker = try ctx.await(handleUpdates, .{});
    self.waker = try self.group.await(Scanner.handleActions, .{ scanner, arena, waker });

    try scanner.actions.putOne(self.io, .initial_scan);
    try self.waker.wake();
}

pub fn deinit(self: *Worktree) void {
    self.snapshot.deinit(self.gpa);
    self.scanner.stop();
    self.handler.cancel();
    self.group.cancel();
}

fn handleUpdates(ctx: Context(Worktree), res: anyerror!void) bool {
    res catch return false;
    _handleUpdates(ctx) catch return false;

    return true;
}

fn _handleUpdates(ctx: Context(Worktree)) !void {
    const self, const update = ctx.update();
    defer update.end(self);

    var buffer: [8]Updates = undefined;
    var updates = &self.scanner.updates;
    for (0..try updates.get(self.io, &buffer, 0)) |idx| {
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
