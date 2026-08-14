const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const Io = std.Io;
const atomic = std.atomic;
const heap = std.heap;
const assert = std.debug.assert;

const App = @import("app.zig");
const chunk_pool = @import("chunk_pool.zig");
const ChunkedPath = @import("chunked_path.zig");
const datastruct = @import("datastruct.zig");
const MpscBounded = datastruct.MpscBounded;
const ent = @import("entity.zig");
const AnyEntity = ent.AnyEntity;
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
app: *App,
gpa: Allocator,
any: AnyEntity,
arena: heap.ArenaAllocator,
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
    any: AnyEntity,
    app: *App,
    io: Io,
    abs_path: []const u8,
) !void {
    const gpa = app.gpa;

    self.* = .{
        .any = any,
        .app = app,
        .io = io,
        .gpa = gpa,
        .arena = .init(gpa),
        .scanning = false,
        .snapshot = undefined,
        .scanner = undefined,
        .stopped = false,
        .await = .noop,
        .await_c = .noop,
        .waker = undefined,
        .events = undefined,
    };

    try self.snapshot.init(abs_path, gpa, io);

    const arena = self.arena.allocator();
    errdefer self.arena.deinit();

    self.events = try .init(state.cpu_count, 64, arena);
    self.waker = try app.await(&self.await, handleEvents);

    try self.scanner.init(&app.scheduler, gpa, self.arena.allocator(), io);
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
    if (self.scanner.stop()) {
        self.any.drop();
        self.app.cancel(
            &self.await_c,
            struct {
                fn noop(_: *Completion, _: void) bool {
                    return false;
                }
            }.noop,
            &self.await,
        );
        self.waker.close();
    } else {
        self.stopped = true;
    }
}

pub const Event = union(enum) {
    update: struct {
        snapshot: Snapshot,
        scanning: bool,
    },
    started,

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

    const update = self.app.update(self);
    defer update.end();

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

                if (!self.scanning and self.stopped) {
                    self.drop();
                }
            },
        }
    }
    self.app.notify(self);

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
    defer worktree.drop();

    try testing.expectEqualStrings(worktree.snapshot.abs_root, chromium_path);
}

test {
    _ = bench;
}
