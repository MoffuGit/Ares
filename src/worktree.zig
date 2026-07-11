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
const sch = @import("scheduler.zig");
const BackgroundScheduler = sch.BackgroundScheduler;
const Executor = BackgroundScheduler.Executor;
const Scheduler = sch.Scheduler;

pub const Worktree = @This();

pub const Options = struct {
    abs_path: []const u8,
};

io: Io,
gpa: Allocator,
scanning: bool,
snapshot: Snapshot,
scanner: Executor(Scanner),
waker: sch.Waker,

pub fn init(self: *Worktree, ctx: Context(Worktree), io: Io, arena: Allocator, opts: Options) !void {
    self.* = .{
        .io = io,
        .gpa = ctx.gpa(),
        .scanning = false,
        .snapshot = undefined,
        .scanner = undefined,
        .waker = undefined,
    };

    const abs_root = try arena.dupe(u8, opts.abs_path);
    const root_name = try arena.dupe(u8, path.basename(abs_root));

    try self.snapshot.init(abs_root, root_name, self.gpa);
    errdefer self.snapshot.deinit(self.gpa);

    self.waker = try ctx.await(handleUpdates, .{});
    errdefer self.waker.close();

    self.scanner = try ctx.executor(Scanner, Scanner.handleActions, .{ arena, self.waker });
    try self.scanner.init(.{
        &self.snapshot,
        ctx.gpa(),
        io,
    });
}

pub fn deinit(self: *Worktree) void {
    self.waker.close();
    self.scanner.stop();
    self.snapshot.deinit(self.gpa);
}

fn handleUpdates(ctx: Context(Worktree)) bool {
    _handleUpdates(ctx) catch return false;

    return true;
}

fn _handleUpdates(ctx: Context(Worktree)) !void {
    const self, const update = ctx.update();
    defer update.end(self);

    var buffer: [8]Updates = undefined;
    const updates = &self.scanner.ptr.updates;
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
    try app.init(.{}, gpa, io);
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
