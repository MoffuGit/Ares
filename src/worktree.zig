const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Io = std.Io;
const atomic = std.atomic;

const App = @import("app.zig");
const Entity = App.Entity;
const Context = App.Context;
const Receivers = App.Receivers;
const ect = @import("executor.zig");
const Executor = ect.Executor;
const bench = @import("worktree/bench.zig");
const Scanner = @import("worktree/scanner.zig");
const Updates = Scanner.Updates;
const Snapshot = @import("worktree/snapshot.zig");

const log = std.log.scoped(.worktree);

pub const Worktree = @This();

pub const Options = struct {
    abs_path: []const u8,
};

io: Io,
gpa: Allocator,
scanning: bool,
snapshot: Snapshot,
scanner: Executor(Scanner),
update_subscription: Receivers.Subscription,

pub fn init(self: *Worktree, ctx: Context(Worktree), io: Io, opts: Options) !void {
    self.* = .{
        .io = io,
        .gpa = ctx.gpa(),
        .scanning = false,
        .snapshot = undefined,
        .scanner = undefined,
        .update_subscription = undefined,
    };

    self.update_subscription = try ctx.receive(Scanner.Updates, handleUpdates, .{});
    errdefer self.update_subscription.unsubscribe() catch {};
    self.scanner = try ctx.executor(Scanner, .{ self.update_subscription, opts.abs_path, ctx.gpa(), io });

    const ptr = self.scanner.ptr;
    self.snapshot = try ptr.snapshot.clone(ctx.gpa());
}

pub fn deinit(self: *Worktree) void {
    self.update_subscription.unsubscribe() catch {};
    self.scanner.drop();
    self.snapshot.deinit();
}

fn handleUpdates(self: *Worktree, updates: *Scanner.Updates, _: Context(Worktree)) bool {
    switch (updates.*) {
        .started => {
            log.debug("scanner for path \"{s}\" started", .{self.snapshot.abs_root});
            self.scanning = true;
        },
        .updated => |updated| {
            self.snapshot.deinit();
            self.snapshot = updated.snapshot;
            self.scanning = updated.scanning;

            log.debug("scanner for path \"{s}\" update", .{self.snapshot.abs_root});
            if (!self.scanning) {
                log.debug("scanner for path \"{s}\" ended", .{self.snapshot.abs_root});
            }
        },
    }

    return true;
}

test {
    _ = Scanner;
    _ = bench;
}
