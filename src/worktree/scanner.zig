//TODO:
//I need to check all the try/catch/defer/errdefer points
//i didn't care becaues i wanted to test the scheduler

const std = @import("std");
const Io = std.Io;
const c = std.c;
const atomic = std.atomic;
const posix = std.posix;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const heap = std.heap;
const Timestamp = Io.Timestamp;
const builtin = @import("builtin");

const GitIgnore = @import("zlob").GitIgnore;

const App = @import("../app.zig");
const Context = App.Context;
const chunk_pool = @import("../chunk_pool.zig");
const ChunkAllocator = chunk_pool.ChunkAllocator;
const ChunkedPath = @import("../chunked_path.zig");
const RANGE_NODE_SIZE = ChunkedPath.RANGE_NODE_SIZE;
const CHUNK_SIZE = ChunkedPath.CHUNKS_SIZE;
const constants = @import("../constants.zig");
const MAX_PATH_LEN = constants.MAX_PATH_LEN;
const datastruct = @import("../datastruct.zig");
const SinglyLinkedList = datastruct.SinglyLinkedList;
const Dequeue = datastruct.Dequeue;
const global = @import("../global.zig");
const Loop = @import("../loop.zig");
const Completion = Loop.Completion;
const Waker = Loop.Waker;
const Scheduler = @import("../scheduler.zig");
const Task = Scheduler.Task;
const Worker = Scheduler.Worker;
const Worktree = @import("../worktree.zig");
const Event = Worktree.Event;
const attr = @import("attr.zig");
const BulkAttr = attr.BulkAttr;
const Snapshot = @import("snapshot.zig");

const UPDATE_INTERVAL_IN_MS = if (builtin.mode == .Debug) 2000 else 100;
const log = std.log.scoped(.scanner);

const Scanner = @This();

io: Io,
gpa: Allocator,
arena: Allocator,
snapshot: Snapshot,
mutex: Io.Mutex,
chunks: ChunkAllocator,
last_update: atomic.Value(i64),
next_scan_id: atomic.Value(u64),
task_count: atomic.Value(u64),
stopped: atomic.Value(bool),

pub fn init(
    self: *Scanner,
    scheduler: *Scheduler,
    gpa: Allocator,
    arena: Allocator,
    io: Io,
) !void {
    self.* = .{
        .gpa = gpa,
        .arena = arena,
        .io = io,
        .snapshot = undefined,
        .mutex = .init,
        .chunks = undefined,
        .last_update = .init(Timestamp.now(io, .real).toMilliseconds()),
        .next_scan_id = .init(0),
        .task_count = .init(0),
        .stopped = .init(false),
    };

    self.snapshot = try self.parent().snapshot.clone(self.gpa);

    try self.chunks.initThreadSafe(
        self.arena,
        &.{
            .{ 1024 * 1024 * 1024, RANGE_NODE_SIZE },
            .{ 1024 * 1024 * 1024, CHUNK_SIZE },
            .{ 1024 * 1024, @sizeOf(ScannerTask) },
            .{ 1024 * 1024, @sizeOf(SharedFd) },
            .{ 1024 * 1024, @sizeOf(EntryData) },
        },
        self.io,
    );

    const chunks = self.chunks.threadSafeAllocator();

    const task = try chunks.create(ScannerTask);
    task.* = .{
        .scanner = self,
        .kind = .initial_scan,
        .task = .{
            .callback = handleTask,
        },
    };

    try scheduler.push(&task.task);
    self.task_count.store(1, .release);
}

pub fn deinit(self: *Scanner) void {
    self.snapshot.deinit();
}

pub fn stop(self: *Scanner) bool {
    self.stopped.store(true, .release);
    return self.task_count.load(.acquire) == 0;
}

const ScannerTask = struct {
    scanner: *Scanner,
    kind: union(enum) {
        initial_scan,
        scan_dir: struct {
            path: ChunkedPath,
            shared_fd: ?*SharedFd,
            ignore: ?*const IgnoreNode,
        },
    },
    task: Task,
};

pub inline fn parent(self: *Scanner) *Worktree {
    return @fieldParentPtr("scanner", self);
}

fn taskDone(self: *Scanner, task: *ScannerTask) void {
    const chunks = self.chunks.threadSafeAllocator();
    defer chunks.destroy(task);

    const prev = self.task_count.fetchSub(1, .release);
    if (prev != 1) return;

    const worktree = self.parent();
    defer worktree.waker.wake() catch unreachable;

    var producer = worktree.events.register() orelse unreachable;
    defer producer.unregister();

    if (self.stopped.load(.acquire)) {
        producer.push(.stopped);
    } else {
        producer.push(.{
            .update = .{
                .scanning = false,
                .snapshot = self.snapshot.clone(self.gpa) catch unreachable,
            },
        });
    }
}

fn handleTask(task: *Task) void {
    const t: *ScannerTask = @fieldParentPtr("task", task);

    const self = t.scanner;
    defer self.taskDone(t);

    if (self.stopped.load(.acquire)) return;

    switch (t.kind) {
        .initial_scan => self.initialScan() catch |err| {
            switch (err) {
                error.Closed => {},
                else => log.err("Initial Scan err={}", .{err}),
            }
        },
        .scan_dir => |dir| {
            self.scanDir(dir.path, dir.shared_fd, dir.ignore) catch |err| {
                switch (err) {
                    error.Closed => {},
                    else => log.err("Initial Scan err={}", .{err}),
                }
            };
        },
    }
}

fn initialScan(
    self: *Scanner,
) !void {
    const worker = Worker.local orelse unreachable;
    const chunks = self.chunks.threadSafeAllocator();
    const worktree = self.parent();

    const stat = try Io.Dir.statFile(
        .cwd(),
        self.io,
        self.snapshot.abs_root,
        .{},
    );

    const path: ChunkedPath = .new(self.snapshot.root_name, 0, chunks);

    {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);

        self.snapshot.insert(
            path,
            .{
                .inode = stat.inode,
                .size = stat.size,
                .mtime = stat.mtime,
                .kind = stat.kind,
                .hidden = false,
                .ignored = false,
                .state = .pending,
            },
        );
    }

    if (stat.kind != .directory) return;

    {
        var producer = worktree.events.register() orelse unreachable;
        defer producer.unregister();

        producer.push(.started);
        try worktree.waker.wake();
    }

    const task = chunks.create(ScannerTask) catch unreachable;
    errdefer chunks.destroy(task);

    task.* = .{
        .scanner = self,
        .kind = .{
            .scan_dir = .{
                .path = path,
                .shared_fd = null,
                .ignore = null,
            },
        },
        .task = .{ .callback = handleTask },
    };

    try worker.push(&task.task);
    _ = self.task_count.fetchAdd(1, .release);
}

const IgnoreNode = struct {
    gi: GitIgnore,
    relative_offset: u32,

    parent: ?*const IgnoreNode,
};

fn isIgnored(
    start: ?*const IgnoreNode,
    path: []const u8,
    basename: []const u8,
    is_dir: bool,
) bool {
    var node = start;
    while (node) |n| : (node = n.parent) {
        if (n.gi.is_empty) continue;

        if (n.gi.checkWithBasename(
            path[n.relative_offset..],
            basename,
            is_dir,
        )) |verdict| {
            return verdict;
        }
    }
    return false;
}

const EntryData = struct {
    path: ChunkedPath,
    meta: Snapshot.Meta,
    next: ?*EntryData = null,
};

const SharedFd = struct {
    dir: Io.Dir,
    refs: atomic.Value(u32),

    pub fn init(self: *SharedFd, dir: Io.Dir, refs: u32) void {
        self.* = .{
            .dir = dir,
            .refs = .init(refs),
        };
    }

    fn release(self: *SharedFd) u32 {
        return self.refs.fetchSub(1, .acq_rel);
    }

    fn close(self: *SharedFd, io: Io) void {
        self.dir.close(io);
    }
};

fn scanDir(self: *Scanner, dir_path: ChunkedPath, shared_fd: ?*SharedFd, ignore: ?*const IgnoreNode) !void {
    const chunks = self.chunks.threadSafeAllocator();
    var buffer: [64 * 1024]u8 = undefined;
    var tasks: SinglyLinkedList(Task) = .{};
    //     errdefer {
    //         while (jobs.pop()) |j| {
    //             j.finish(chunks, self.io);
    //         }
    //     }
    var count: u32 = 0;

    const dir = bkl: {
        if (shared_fd) |fd| {
            const len = dir_path.basename(&buffer);
            break :bkl try fd.dir.openDir(self.io, buffer[0..len], .{ .follow_symlinks = false, .iterate = true });
        }

        break :bkl try Io.Dir.openDirAbsolute(self.io, self.snapshot.abs_root, .{ .follow_symlinks = false, .iterate = true });
    };
    errdefer dir.close(self.io);

    defer if (shared_fd) |fd| {
        const prev = fd.release();

        assert(prev != 0);
        if (prev == 1) {
            fd.close(self.io);
            chunks.destroy(fd);
        }
    };

    var effective_ignore: ?*const IgnoreNode = ignore;
    {
        const content = dir.readFile(self.io, ".gitignore", &buffer) catch null;

        if (content) |src| {
            const gi = try GitIgnore.parse(self.arena, src);
            const node = try self.arena.create(IgnoreNode);
            node.* = .{
                .parent = ignore,
                .gi = gi,
                .relative_offset = dir_path.len + 1,
            };
            effective_ignore = node;
        }
    }

    var bulk = BulkAttr.init(dir.handle, &buffer, .{
        .size = true,
        .mtime = true,
        .inode = true,
    });

    var suffix_buf: [MAX_PATH_LEN]u8 = undefined;
    suffix_buf[0] = '/';
    var path_buf: [MAX_PATH_LEN]u8 = undefined;

    var entries: SinglyLinkedList(EntryData) = .{};

    while (try bulk.next()) |entry| {
        const name = entry.name;
        @memcpy(suffix_buf[1 .. 1 + name.len], name);
        const suffix = suffix_buf[0 .. 1 + name.len];
        const is_dir = entry.kind == .directory;
        const is_hidden = name.len > 0 and name[0] == '.';

        const path: ChunkedPath = .extend(dir_path, suffix, 1, chunks);
        const len = path.read(&path_buf);
        const ignored = isIgnored(effective_ignore, path_buf[0..len], name, is_dir);

        const data = chunks.create(EntryData) catch unreachable;
        data.* = .{
            .path = path,
            .meta = .{
                .state = bkl: {
                    if (entry.kind == .directory) {
                        break :bkl if (is_hidden or ignored) .unloaded else .pending;
                    } else break :bkl .loaded;
                },
                .inode = entry.meta.inode,
                .mtime = .fromNanoseconds(@intCast(entry.meta.mtime_ns)),
                .size = entry.meta.size,
                .kind = entry.kind,
                .hidden = is_hidden,
                .ignored = ignored,
            },
        };
        entries.append(data);

        if (is_dir and !(is_hidden or ignored)) {
            const task = try chunks.create(ScannerTask);
            task.* = .{
                .scanner = self,
                .task = .{ .callback = handleTask },
                .kind = .{
                    .scan_dir = .{
                        .shared_fd = null,
                        .path = path,
                        .ignore = effective_ignore,
                    },
                },
            };

            tasks.append(&task.task);
            count += 1;
        }
    }

    {
        try self.mutex.lock(self.io);
        defer self.mutex.unlock(self.io);

        while (entries.pop()) |data| {
            self.snapshot.insert(
                data.path,
                data.meta,
            );
            chunks.destroy(data);
        }

        const entry = self.snapshot.entries.get_mut(dir_path) orelse unreachable;
        entry.meta.state = .loaded;
    }

    if (count > 0) {
        const shared = try chunks.create(SharedFd);
        shared.* = .{
            .dir = dir,
            .refs = .init(count),
        };

        const worker = Worker.local orelse unreachable;

        while (tasks.pop()) |task| {
            const scanner_task: *ScannerTask = @fieldParentPtr("task", task);
            scanner_task.kind.scan_dir.shared_fd = shared;
            try worker.push(task);
            _ = self.task_count.fetchAdd(1, .release);
        }
    } else {
        dir.close(self.io);
    }

    const now = Timestamp.now(self.io, .real).toMilliseconds();
    const last = self.last_update.load(.acquire);

    if (now - last >= UPDATE_INTERVAL_IN_MS) {
        if (self.last_update.cmpxchgWeak(last, now, .acq_rel, .monotonic) == null) {
            const worktree = self.parent();
            var producer = worktree.events.register() orelse unreachable;
            defer producer.unregister();

            self.mutex.lock(self.io) catch unreachable;
            defer self.mutex.unlock(self.io);

            producer.push(.{
                .update = .{
                    .scanning = true,
                    .snapshot = try self.snapshot.clone(self.gpa),
                },
            });

            try worktree.waker.wake();
        }
    }
}
