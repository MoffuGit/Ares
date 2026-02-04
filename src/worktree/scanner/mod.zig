const std = @import("std");
const Allocator = std.mem.Allocator;
const worktreepkg = @import("../mod.zig");
const Worktree = worktreepkg.Worktree;
const Entry = worktreepkg.Entry;
const Kind = worktreepkg.Kind;
const Snapshot = @import("../Snapshot.zig");
const MonitorMessage = @import("../monitor/Message.zig").Message;
// const AppEvent = @import("../../AppEvent.zig");

pub const Scanner = @This();

pub const UpdatedEntriesSet = struct {
    pub const Update = union(enum) {
        add: Entry,
        update: Entry,
        delete: []const u8,
    };

    alloc: Allocator,
    updates: std.ArrayListUnmanaged(Update),
    applied: bool = false,

    pub fn init(alloc: Allocator) UpdatedEntriesSet {
        return .{
            .alloc = alloc,
            .updates = .{},
            .applied = false,
        };
    }

    pub fn deinit(self: *UpdatedEntriesSet) void {
        if (!self.applied) {
            for (self.updates.items) |update| {
                switch (update) {
                    .add => |entry| self.alloc.free(entry.path),
                    .update => {},
                    .delete => |path| self.alloc.free(path),
                }
            }
        }
        self.updates.deinit(self.alloc);
    }

    pub fn destroy(self: *UpdatedEntriesSet) void {
        self.deinit();
        self.alloc.destroy(self);
    }

    pub fn addEntry(self: *UpdatedEntriesSet, entry: Entry) !void {
        try self.updates.append(self.alloc, .{ .add = entry });
    }

    pub fn updateEntry(self: *UpdatedEntriesSet, entry: Entry) !void {
        try self.updates.append(self.alloc, .{ .update = entry });
    }

    pub fn deleteEntry(self: *UpdatedEntriesSet, path: []const u8) !void {
        try self.updates.append(self.alloc, .{ .delete = path });
    }

    pub fn apply(self: *UpdatedEntriesSet, snapshot: *Snapshot, scanner: *Scanner) !void {
        snapshot.mutex.lock();
        defer snapshot.mutex.unlock();

        for (self.updates.items) |*update| {
            switch (update.*) {
                .add => |entry| {
                    try snapshot.entries.insert(entry.path, entry);
                    try snapshot.id_to_path.put(entry.id, entry.path);

                    // If it's a directory, add a watcher
                    if (entry.kind == .dir) {
                        const abs_path = try std.fmt.allocPrint(self.alloc, "{s}/{s}", .{
                            scanner.abs_path[0 .. scanner.abs_path.len - scanner.root.len - 1],
                            entry.path,
                        });
                        if (scanner.worktree.monitor_thread.mailbox.push(.{ .add = .{ .path = abs_path, .id = entry.id } }, .instant) == 0) {
                            self.alloc.free(abs_path);
                        } else {
                            scanner.worktree.monitor_thread.wakeup.notify() catch {};
                        }
                    }

                    // Transfer ownership - don't free in deinit
                    update.* = .{ .update = entry };
                },
                .update => |entry| {
                    if (snapshot.entries.get(entry.path) catch null) |existing| {
                        var updated = existing;
                        updated.kind = entry.kind;
                        try snapshot.entries.insert(entry.path, updated);
                    }
                },
                .delete => |path| {
                    if (snapshot.entries.get(path) catch null) |existing| {
                        const id = existing.id;
                        const is_dir = existing.kind == .dir;

                        // Remove from id_to_path
                        _ = snapshot.id_to_path.remove(id);

                        // Remove watcher if it's a directory
                        if (is_dir) {
                            if (scanner.worktree.monitor_thread.mailbox.push(.{ .remove = id }, .instant) != 0) {
                                scanner.worktree.monitor_thread.wakeup.notify() catch {};
                            }
                        }
                    }

                    // Remove from entries
                    _ = snapshot.entries.remove(path) catch null;

                    // Free path - ownership transferred, mark as handled
                    self.alloc.free(path);
                    update.* = .{ .update = .{ .id = 0, .kind = .file, .path = "" } };
                },
            }
        }

        _ = snapshot.version.fetchAdd(1, .monotonic);
        self.applied = true;
    }

    // pub fn notifyApp(self: *UpdatedEntriesSet, scanner: *Scanner) void {
    //     scanner.worktree.notifyAppEvent(.{ .worktree_updated = self });
    // }
};

alloc: Allocator,
worktree: *Worktree,

abs_path: []u8,
root: []u8,
snapshot: *Snapshot,

pub fn init(alloc: Allocator, worktree: *Worktree, snapshot: *Snapshot, abs_path: []u8, root: []u8) !Scanner {
    const _root = try alloc.dupe(u8, root);
    errdefer alloc.free(_root);
    const _abs_path = try alloc.dupe(u8, abs_path);
    errdefer alloc.free(_abs_path);

    return .{ .alloc = alloc, .worktree = worktree, .abs_path = _abs_path, .root = _root, .snapshot = snapshot };
}

pub fn deinit(self: *Scanner) void {
    self.alloc.free(self.abs_path);
    self.alloc.free(self.root);
}

pub fn process_scan(self: *Scanner, path: []const u8, abs_path: []const u8) !void {
    var dir = try std.fs.openDirAbsolute(abs_path, .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        const kind: Kind = switch (entry.kind) {
            .directory => .dir,
            .file => .file,
            else => continue,
        };
        const child_path = try std.fmt.allocPrint(self.alloc, "{s}/{s}", .{ path, entry.name });

        const id = self.snapshot.next_id.fetchAdd(1, .monotonic);
        {
            self.snapshot.mutex.lock();
            defer self.snapshot.mutex.unlock();

            try self.snapshot.entries.insert(child_path, .{ .id = id, .kind = kind, .path = child_path });
            try self.snapshot.id_to_path.put(id, child_path);
            std.log.debug("{s}", .{child_path});
        }

        if (kind == .dir) {
            const child_abs_path = try std.fmt.allocPrint(self.alloc, "{s}/{s}", .{ abs_path, entry.name });
            if (self.worktree.scanner_thread.mailbox.push(.{ .scan = .{ .abs_path = child_abs_path, .path = child_path } }, .instant) == 0) {
                self.alloc.free(child_abs_path);
            }

            const monitor_path = try std.fmt.allocPrint(self.alloc, "{s}/{s}", .{ abs_path, entry.name });
            if (self.worktree.monitor_thread.mailbox.push(.{ .add = .{ .path = monitor_path, .id = id } }, .instant) == 0) {
                self.alloc.free(monitor_path);
            } else {
                self.worktree.monitor_thread.wakeup.notify() catch {};
            }
        }
    }
    try self.worktree.scanner_thread.wakeup.notify();
}

pub fn process_events(self: *Scanner, fs_events: *std.AutoHashMap(u64, u32)) !*UpdatedEntriesSet {
    const result = try self.alloc.create(UpdatedEntriesSet);
    result.* = UpdatedEntriesSet.init(self.alloc);
    errdefer result.destroy();

    var it = fs_events.iterator();
    while (it.next()) |event| {
        const id = event.key_ptr.*;
        const dir_path = self.snapshot.id_to_path.get(id) orelse continue;

        const abs_dir_path = try std.fmt.allocPrint(self.alloc, "{s}/{s}", .{
            self.abs_path[0 .. self.abs_path.len - self.root.len - 1],
            dir_path,
        });
        defer self.alloc.free(abs_dir_path);

        try self.diffDirectory(dir_path, abs_dir_path, result);
    }

    return result;
}

fn diffDirectory(self: *Scanner, dir_path: []const u8, abs_dir_path: []const u8, result: *UpdatedEntriesSet) !void {
    var current_children = std.StringHashMap(Entry).init(self.alloc);
    defer current_children.deinit();

    // Collect current children from snapshot
    {
        self.snapshot.mutex.lock();
        defer self.snapshot.mutex.unlock();

        var entries_it = self.snapshot.entries.iter();
        while (entries_it.next()) |entry| {
            const entry_path = entry.key;
            // Check if this is a direct child of dir_path
            if (std.mem.startsWith(u8, entry_path, dir_path) and entry_path.len > dir_path.len) {
                const suffix = entry_path[dir_path.len..];
                if (suffix[0] == '/') {
                    const rest = suffix[1..];
                    // Direct child has no more slashes
                    if (std.mem.indexOf(u8, rest, "/") == null) {
                        try current_children.put(entry_path, entry.value);
                    }
                }
            }
        }
    }

    // Scan the actual directory
    var dir = std.fs.openDirAbsolute(abs_dir_path, .{ .iterate = true }) catch |err| {
        // Directory might have been deleted
        if (err == error.FileNotFound) {
            // Mark all current children as deleted
            var children_it = current_children.iterator();
            while (children_it.next()) |child| {
                const deleted_path = try self.alloc.dupe(u8, child.key_ptr.*);
                try result.deleteEntry(deleted_path);
            }
        }
        return;
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        const kind: Kind = switch (entry.kind) {
            .directory => .dir,
            .file => .file,
            else => continue,
        };

        const child_path = try std.fmt.allocPrint(self.alloc, "{s}/{s}", .{ dir_path, entry.name });

        if (current_children.fetchRemove(child_path)) |existing| {
            // Entry exists - check if kind changed
            if (existing.value.kind != kind) {
                try result.updateEntry(.{ .id = existing.value.id, .kind = kind, .path = existing.value.path });
            }
            self.alloc.free(child_path);
        } else {
            // New entry
            const id = self.snapshot.next_id.fetchAdd(1, .monotonic);
            try result.addEntry(.{ .id = id, .kind = kind, .path = child_path });
        }
    }

    // Remaining entries in current_children were deleted
    var remaining_it = current_children.iterator();
    while (remaining_it.next()) |child| {
        const deleted_path = try self.alloc.dupe(u8, child.key_ptr.*);
        try result.deleteEntry(deleted_path);
    }
}

pub fn initial_scan(self: *Scanner) !void {
    const fd = try std.posix.open(self.abs_path, .{}, 0);
    defer std.posix.close(fd);

    const fstat = try std.posix.fstat(fd);
    const stat = std.fs.File.Stat.fromPosix(fstat);

    const kind: Kind = switch (stat.kind) {
        .file => .file,
        .directory => .dir,
        else => return error.InvalidKind,
    };

    const id = self.snapshot.next_id.fetchAdd(1, .monotonic);
    const root_path = try self.alloc.dupe(u8, self.root);
    errdefer self.alloc.free(root_path);
    {
        self.snapshot.mutex.lock();
        defer self.snapshot.mutex.unlock();

        try self.snapshot.entries.insert(root_path, .{ .id = id, .kind = kind, .path = root_path });
        try self.snapshot.id_to_path.put(id, root_path);

        try self.snapshot.entries.print();
    }

    if (kind == .dir) {
        const scan_abs_path = try self.alloc.dupe(u8, self.abs_path);
        if (self.worktree.scanner_thread.mailbox.push(.{ .scan = .{ .abs_path = scan_abs_path, .path = root_path } }, .instant) == 0) {
            self.alloc.free(scan_abs_path);
        } else {
            try self.worktree.scanner_thread.wakeup.notify();
        }

        const monitor_path = try self.alloc.dupe(u8, self.abs_path);
        if (self.worktree.monitor_thread.mailbox.push(.{ .add = .{ .path = monitor_path, .id = id } }, .instant) == 0) {
            self.alloc.free(monitor_path);
        } else {
            self.worktree.monitor_thread.wakeup.notify() catch {};
        }
    }
}
