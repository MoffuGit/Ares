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

const state = &global.state;

const log = std.log.scoped(.worktree);

pub const Worktree = @This();

pub const Options = struct {
    abs_path: []const u8,
};

io: Io,
gpa: Allocator,
arena: heap.ArenaAllocator,
ctx: Context(Worktree),
scanning: bool,
snapshot: Snapshot,
scanner: Scanner,
events: Events,

waker: Waker,
await: Completion,
await_c: Completion,

pub fn init(self: *Worktree, ctx: Context(Worktree), io: Io, opts: Options) !void {
    const gpa = ctx.gpa();

    self.* = .{
        .io = io,
        .gpa = gpa,
        .arena = .init(gpa),
        .scanning = false,
        .snapshot = undefined,
        .scanner = undefined,
        .ctx = ctx,
        .await = .noop,
        .await_c = .noop,
        .waker = undefined,
        .events = undefined,
    };

    try self.snapshot.init(opts.abs_path, gpa, io);

    const arena = self.arena.allocator();
    errdefer self.arena.deinit();

    self.events = try .init(state.cpu_count, 16, arena);
    self.waker = try ctx.await(&self.await, handleEvents, self);

    try self.scanner.init(gpa, self.arena.allocator(), io);
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

pub fn drop(self: *Worktree) void {
    self.ctx.cancel(&self.await_c, &self.await);
    self.waker.close();
}

pub const Events = MpscBounded(Event);

pub const Event = union(enum) {
    started: void,
    update: struct {
        snapshot: Snapshot,
        scanning: bool,
    },

    pub fn deinit(self: *Event) void {
        switch (self.*) {
            .update => |*updated| {
                updated.snapshot.deinit();
            },
            else => {},
        }
    }
};

fn handleEvents(self: *Worktree, res: anyerror!void) bool {
    res catch return false;
    while (self.events.pop()) |event| {
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
