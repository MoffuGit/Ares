const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Io = std.Io;
const atomic = std.atomic;
const heap = std.heap;
const assert = std.debug.assert;

const App = @import("app.zig");
const Context = App.Context;
const chunk_pool = @import("chunk_pool.zig");
const ChunkedPath = @import("chunked_path.zig");
const datastruct = @import("datastruct.zig");
const MpscBounded = datastruct.MpscBounded;
const ent = @import("entity.zig");
const Entity = ent.Entity;
const global = @import("global.zig");
const Loop = @import("loop.zig");
const Waker = Loop.Waker;
const Completion = Loop.Completion;
const bench = @import("worktree/bench.zig");
const Scanner = @import("worktree/scanner.zig");
const Snapshot = @import("worktree/snapshot.zig");
const Entry = Snapshot.Entry;

const log = std.log.scoped(.worktree);
const state = &global.state;

pub const Worktree = @This();

io: Io,
gpa: Allocator,
arena: heap.ArenaAllocator,
ctx: Context(Worktree),
scanning: bool,
stopped: bool,
snapshot: Snapshot,
scanner: Scanner,
events: MpscBounded(Event),

waker: Waker,
await: Completion,
await_c: Completion,

pub fn init(
    self: *Worktree,
    ctx: Context(Worktree),
    io: Io,
    abs_path: []const u8,
) !void {
    const gpa = ctx.gpa();

    self.* = .{
        .io = io,
        .gpa = gpa,
        .arena = .init(gpa),
        .scanning = false,
        .snapshot = undefined,
        .scanner = undefined,
        .stopped = false,
        .ctx = ctx,
        .await = .noop,
        .await_c = .noop,
        .waker = undefined,
        .events = undefined,
    };

    try self.snapshot.init(abs_path, gpa, io);

    const arena = self.arena.allocator();
    errdefer self.arena.deinit();

    self.events = try .init(state.cpu_count, 64, arena);
    self.waker = try ctx.await(&self.await, handleEvents);

    try self.scanner.init(ctx.scheduler(), gpa, self.arena.allocator(), io);
}

pub fn deinit(self: *Worktree) void {
    while (true) {
        var event = self.events.pop() orelse break;
        event.deinit();
    }

    self.scanner.deinit();
    self.snapshot.deinit();
    self.arena.deinit();
}

pub fn stop(self: *Worktree) void {
    self.stopped = self.scanner.stop();

    if (self.stopped) self.ctx.drop();
}

pub fn drop(self: *Worktree) void {
    assert(self.stopped);
    self.ctx.cancel(&self.await_c, &self.await);
    self.waker.close();
}

pub const Event = union(enum) {
    update: struct {
        snapshot: Snapshot,
        scanning: bool,
    },
    started,
    stopped,

    pub fn deinit(self: *Event) void {
        switch (self.*) {
            .update => |*updated| {
                updated.snapshot.deinit();
            },
            else => {},
        }
    }
};

fn handleEvents(c: *Completion, res: anyerror!void) bool {
    res catch return false;

    const self: *Worktree = @fieldParentPtr("await", c);

    const update = self.ctx.update();
    defer self.ctx.endUpdate(&update);

    while (self.events.pop()) |event| {
        switch (event) {
            .stopped => {
                if (self.stopped) continue;
                self.stop();
            },
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

test "Worktree" {
    const gpa = testing.allocator;
    const io = testing.io;
    const chromium_path = @import("test_options").chromium_path;

    var app: App = undefined;
    try app.init(gpa, io);
    defer app.deinit();

    const worktree = try app.new(
        Worktree,
        init,
        .{
            io,
            chromium_path,
        },
    );

    try testing.expectEqualStrings(worktree.read().?.snapshot.abs_root, chromium_path);

    const ptr = worktree.update();
    ptr.stop();
}

test {
    _ = bench;
}
