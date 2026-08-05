const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Io = std.Io;
const atomic = std.atomic;

const App = @import("app.zig");
const Context = App.Context;
const Receiver = App.Receiver;
const ChunkedPath = @import("chunked_path.zig");
const ent = @import("entity.zig");
const Entity = ent.Entity;
const Runner = @import("runner.zig");
const bench = @import("worktree/bench.zig");
const Scanner = @import("worktree/scanner.zig");
const Event = Scanner.Event;
const Snapshot = @import("worktree/snapshot.zig");
const Entry = Snapshot.Entry;

const log = std.log.scoped(.worktree);

pub const Worktree = @This();

pub const Options = struct {
    abs_path: []const u8,
};

io: Io,
gpa: Allocator,
scanning: bool,
snapshot: Snapshot,
scanner: *Scanner,
subscription: Receiver,

pub fn init(self: *Worktree, ctx: Context(Worktree), io: Io, opts: Options) !void {
    self.* = .{
        .io = io,
        .gpa = ctx.gpa(),
        .scanning = false,
        .snapshot = undefined,
        .scanner = undefined,
        .subscription = undefined,
    };

    self.subscription = try ctx.receive(Scanner.Event, handleUpdates, .{});
    errdefer self.subscription.unsubscribe() catch {};

    const runner = ctx.runner();
    self.scanner = try runner.create(Scanner);
    try self.scanner.init(runner, self.subscription, opts.abs_path, ctx.gpa(), io);

    self.snapshot = try self.scanner.snapshot.clone(ctx.gpa());
}

pub fn deinit(self: *Worktree) void {
    self.subscription.unsubscribe() catch {};
    self.scanner.drop();
    self.snapshot.deinit();
}

fn handleUpdates(self: *Worktree, updates: *Scanner.Event, ctx: Context(Worktree)) bool {
    switch (updates.*) {
        .started => {
            log.debug("scanner for path \"{s}\" started", .{self.snapshot.abs_root});
            self.scanning = true;
        },
        .update => |updated| {
            self.snapshot.deinit();
            self.snapshot = updated.snapshot;
            self.scanning = updated.scanning;

            log.debug("scanner for path \"{s}\" update", .{self.snapshot.abs_root});
            if (!self.scanning) {
                log.debug("scanner for path \"{s}\" ended", .{self.snapshot.abs_root});
            }
        },
    }

    ctx.notify();

    return true;
}

test {
    _ = Scanner;
    _ = bench;

    const gpa = testing.allocator;
    const io = testing.io;
    const chromium_path = @import("test_options").chromium_path;

    var app: App = undefined;
    try app.init(.{}, gpa, io);
    defer app.deinit();

    const worktree: Entity(Worktree) = try .new(
        &app,
        .{
            io,
            Worktree.Options{
                .abs_path = chromium_path,
            },
        },
    );
    defer worktree.drop();

    try testing.expectEqualStrings(worktree.read().snapshot.abs_root, chromium_path);
}
