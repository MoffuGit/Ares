const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Io = std.Io;
const atomic = std.atomic;

const test_build = @import("test_build");

const App = @import("app.zig");
const Entity = App.Entity;
const Context = App.Context;
const sch = @import("scheduler.zig");
const Executor = sch.Executor;
const Scanner = @import("worktree/scanner.zig");
const Updates = Scanner.Updates;
const Snapshot = @import("worktree/snapshot.zig");

pub const Worktree = @This();

pub const Options = struct {
    abs_path: []const u8,
};

io: Io,
gpa: Allocator,
scanning: bool,
snapshot: Snapshot,
scanner: Executor(Scanner),
waker: App.Waker,

pub fn init(self: *Worktree, ctx: Context(Worktree), io: Io, opts: Options) !void {
    self.* = .{
        .io = io,
        .gpa = ctx.gpa(),
        .scanning = false,
        .snapshot = undefined,
        .scanner = undefined,
        .waker = undefined,
    };

    self.waker = try ctx.await(handleUpdates, .{});
    errdefer self.waker.close();

    self.scanner = try ctx.executor(Scanner, .{ self.waker, opts.abs_path, ctx.gpa(), io });

    self.snapshot = try self.scanner.ptr.snapshot.clone(ctx.gpa());
}

pub fn deinit(self: *Worktree) void {
    self.waker.close();
    self.scanner.drop(self.io) catch {};
    self.snapshot.deinit();
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
            .started => {
                std.log.debug("scanner for path \"{s}\" started", .{self.snapshot.abs_root});
                self.scanning = true;
            },
            .updated => |updated| {
                self.snapshot.deinit();
                self.snapshot = updated.snapshot;
                self.scanning = updated.scanning;

                std.log.debug("scanner for path \"{s}\" update", .{self.snapshot.abs_root});
                if (!self.scanning) {
                    std.log.debug("scanner for path \"{s}\" ended", .{self.snapshot.abs_root});
                }
            },
        }
    }

    ctx.notify();
}

test "Worktree Entity" {
    const gpa = testing.allocator;
    const io = testing.io;

    var app: App = undefined;
    try app.init(.{}, gpa, io);
    defer app.deinit();

    const worktree: Entity(Worktree) = try .new(
        &app,
        .{
            io,
            Options{
                .abs_path = test_build.chromium_path,
            },
        },
    );

    worktree.drop();
    app.flush();
}
