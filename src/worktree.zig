const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Io = std.Io;
const atomic = std.atomic;
const heap = std.heap;

const App = @import("app.zig");
const Context = App.Context;
const chunk_pool = @import("chunk_pool.zig");
const ChunkAllocator = chunk_pool.ChunkAllocator;
const ChunkedPath = @import("chunked_path.zig");
const ent = @import("entity.zig");
const Entity = ent.Entity;
const Loop = @import("loop.zig");
const Waker = Loop.Waker;
const Completion = Loop.Completion;
const bench = @import("worktree/bench.zig");
const Scanner = @import("worktree/scanner.zig");
const Snapshot = @import("worktree/snapshot.zig");
const Entry = Snapshot.Entry;

// const Event = Scanner.Event;
const log = std.log.scoped(.worktree);

pub const Worktree = @This();

pub const Options = struct {
    abs_path: []const u8,
};

io: Io,
gpa: Allocator,
ctx: Context(Worktree),
scanning: bool,
snapshot: Snapshot,
scanner: Scanner,

waker: Waker,
await: Completion,
await_c: Completion,

pub fn init(self: *Worktree, ctx: Context(Worktree), io: Io, opts: Options) !void {
    const gpa = ctx.gpa();

    self.* = .{
        .io = io,
        .gpa = gpa,
        .scanning = false,
        .snapshot = undefined,
        .scanner = undefined,
        .ctx = ctx,
        .await = .noop,
        .await_c = .noop,
        .waker = undefined,
    };

    self.waker = try ctx.app.await(&self.await, handleUpdates, self);

    try self.scanner.init(self.waker, opts.abs_path, ctx.gpa(), io);
    try self.snapshot.init(opts.abs_path, ctx.gpa(), io);
}

pub fn deinit(self: *Worktree) void {
    self.scanner.deinit();
    self.snapshot.deinit();
}

pub fn drop(self: *Worktree) void {
    self.ctx.app.cancel(&self.await_c, &self.await);
    self.waker.close();
}

fn handleUpdates(self: *Worktree, res: anyerror!void) bool {
    res catch return false;
    while (self.scanner.events.pop()) |event| {
        switch (event) {
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
    }

    self.ctx.notify();

    return true;
}

test {
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
