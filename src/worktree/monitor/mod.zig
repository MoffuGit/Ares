const std = @import("std");
const xev = @import("../../global.zig").xev;
const Allocator = std.mem.Allocator;
const Worktree = @import("../mod.zig").Worktree;
const Thread = @import("Thread.zig");

const log = std.log.scoped(.worktree_monitor);

pub const Monitor = @This();

pub const WatcherEntry = struct {
    watcher: xev.FileSystem.Watcher,
    path: []u8,
    id: u64,
    thread: *Thread,
};

alloc: Allocator,
watchers: std.AutoHashMap(u64, *WatcherEntry),
pending_cancel: std.ArrayListUnmanaged(*WatcherEntry),
worktree: *Worktree,

pub fn init(alloc: Allocator, worktree: *Worktree) !Monitor {
    return .{
        .watchers = std.AutoHashMap(u64, *WatcherEntry).init(alloc),
        .pending_cancel = .{},
        .alloc = alloc,
        .worktree = worktree,
    };
}

pub fn deinit(self: *Monitor) void {
    var it = self.watchers.valueIterator();
    while (it.next()) |entry_ptr| {
        const entry = entry_ptr.*;
        self.alloc.free(entry.path);
        self.alloc.destroy(entry);
    }
    self.watchers.deinit();

    for (self.pending_cancel.items) |entry| {
        self.alloc.free(entry.path);
        self.alloc.destroy(entry);
    }
    self.pending_cancel.deinit(self.alloc);
}

pub fn addWatcher(
    self: *Monitor,
    fs: *xev.FileSystem,
    path: []u8,
    id: u64,
    thread: *Thread,
    comptime callback: *const fn (?*WatcherEntry, *xev.FileSystem.Watcher, []const u8, u32) xev.CallbackAction,
) !void {
    if (self.watchers.contains(id)) {
        log.warn("watcher already exists for id={}, ignoring", .{id});
        self.alloc.free(path);
        return;
    }

    const entry = try self.alloc.create(WatcherEntry);
    errdefer self.alloc.destroy(entry);

    entry.* = .{
        .watcher = .{},
        .path = path,
        .id = id,
        .thread = thread,
    };

    fs.watch(path, &entry.watcher, WatcherEntry, entry, callback) catch |err| {
        log.err("failed to start watcher for '{s}': {}", .{ path, err });
        self.alloc.free(path);
        self.alloc.destroy(entry);
        return;
    };

    try self.watchers.put(id, entry);
}

pub fn removeWatcher(self: *Monitor, fs: *xev.FileSystem, id: u64) void {
    if (self.watchers.fetchRemove(id)) |kv| {
        const entry = kv.value;
        fs.cancel(&entry.watcher);
        self.pending_cancel.append(self.alloc, entry) catch |err| {
            log.err("failed to add watcher to pending_cancel queue: {}", .{err});
            self.alloc.free(entry.path);
            self.alloc.destroy(entry);
        };
        log.debug("monitor removing watcher: id={}", .{id});
    } else {
        log.warn("no watcher found for id={}", .{id});
    }
}

pub fn cleanupCancelledWatchers(self: *Monitor) void {
    var i: usize = 0;
    while (i < self.pending_cancel.items.len) {
        const entry = self.pending_cancel.items[i];
        if (entry.watcher.state() == .dead) {
            log.debug("cleaning up dead watcher for id={}", .{entry.id});
            self.alloc.free(entry.path);
            self.alloc.destroy(entry);
            _ = self.pending_cancel.swapRemove(i);
        } else {
            i += 1;
        }
    }
}
