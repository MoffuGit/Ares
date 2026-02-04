const std = @import("std");
const fmt = std.fmt;
const worktreepkg = @import("../mod.zig");

const Worktree = worktreepkg.Worktree;
const Entry = worktreepkg.Entry;
const Kind = worktreepkg.Kind;
const Allocator = std.mem.Allocator;
const Snapshot = @import("../Snapshot.zig");
const MonitorMessage = @import("../monitor/Message.zig").Message;

pub const Scanner = @This();

/// Cross-thread update set. Uses IDs for add/update (lookup path from Snapshot),
/// and owned path copy for delete (since path is removed from Snapshot).
pub const UpdatedEntriesSet = struct {
    pub const Update = union(enum) {
        /// New entry added - lookup path via id from Snapshot
        add: struct { id: u64, kind: Kind },
        /// Entry updated - lookup path via id from Snapshot
        update: struct { id: u64, kind: Kind },
        /// Entry deleted - owns a copy of the path (no longer in Snapshot)
        delete: struct { id: u64, path: []const u8 },
    };

    alloc: Allocator,
    updates: std.ArrayListUnmanaged(Update),

    pub fn init(alloc: Allocator) UpdatedEntriesSet {
        return .{
            .alloc = alloc,
            .updates = .{},
        };
    }

    pub fn deinit(self: *UpdatedEntriesSet) void {
        for (self.updates.items) |update| {
            switch (update) {
                .delete => |d| self.alloc.free(d.path),
                else => {},
            }
        }
        self.updates.deinit(self.alloc);
    }

    pub fn destroy(self: *UpdatedEntriesSet) void {
        self.deinit();
        self.alloc.destroy(self);
    }

    pub fn addEntry(self: *UpdatedEntriesSet, id: u64, kind: Kind) !void {
        try self.updates.append(self.alloc, .{ .add = .{ .id = id, .kind = kind } });
    }

    pub fn updateEntry(self: *UpdatedEntriesSet, id: u64, kind: Kind) !void {
        try self.updates.append(self.alloc, .{ .update = .{ .id = id, .kind = kind } });
    }

    /// Delete entry - takes ownership of the path copy
    pub fn deleteEntry(self: *UpdatedEntriesSet, id: u64, path: []const u8) !void {
        try self.updates.append(self.alloc, .{ .delete = .{ .id = id, .path = path } });
    }
};

alloc: Allocator,
worktree: *Worktree,

abs_root: []const u8,
root_name: []const u8,
snapshot: *Snapshot,

pub fn init(alloc: Allocator, worktree: *Worktree, snapshot: *Snapshot, abs_root: []const u8) !Scanner {
    return .{
        .alloc = alloc,
        .worktree = worktree,
        .abs_root = abs_root,
        .root_name = std.fs.path.basename(abs_root),
        .snapshot = snapshot,
    };
}

pub fn deinit(self: *Scanner) void {
    _ = self;
}

/// Build absolute path on the stack from abs_root + relative path (stripping root_name prefix)
/// rel_path is like "ares/src/file.zig", we need "/path/to/ares/src/file.zig"
fn buildAbsPath(self: *Scanner, rel_path: []const u8, buf: []u8) ![]const u8 {
    // rel_path starts with root_name, we need to replace it with abs_root
    if (std.mem.eql(u8, rel_path, self.root_name)) {
        // Just the root
        return self.abs_root;
    }
    if (std.mem.startsWith(u8, rel_path, self.root_name) and rel_path.len > self.root_name.len and rel_path[self.root_name.len] == '/') {
        // Strip root_name prefix and append to abs_root
        const suffix = rel_path[self.root_name.len..]; // includes leading "/"
        return try std.fmt.bufPrint(buf, "{s}{s}", .{ self.abs_root, suffix });
    }
    // Fallback - shouldn't happen with well-formed paths
    return try std.fmt.bufPrint(buf, "{s}/{s}", .{ self.abs_root, rel_path });
}

/// Scan a directory by entry id (looks up path from Snapshot)
pub fn process_scan_by_id(self: *Scanner, dir_id: u64) !void {
    // Get the relative path from snapshot
    const rel_path = blk: {
        self.snapshot.mutex.lock();
        defer self.snapshot.mutex.unlock();
        break :blk self.snapshot.getPathById(dir_id) orelse return;
    };

    // Build abs path on stack
    var abs_buf: [std.fs.max_path_bytes]u8 = undefined;
    const abs_path = try self.buildAbsPath(rel_path, &abs_buf);

    var dir = try std.fs.openDirAbsolute(abs_path, .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        const kind: Kind = switch (entry.kind) {
            .directory => .dir,
            .file => .file,
            else => continue,
        };

        const id = self.snapshot.newId();

        // Intern path into snapshot arena
        const child_path = blk: {
            self.snapshot.mutex.lock();
            defer self.snapshot.mutex.unlock();

            const interned = try self.snapshot.internPath(rel_path, entry.name);
            try self.snapshot.insertInterned(id, interned, kind);
            break :blk interned;
        };
        _ = child_path;

        if (kind == .dir) {
            // Queue scan for child directory (by id)
            if (self.worktree.scanner_thread.mailbox.push(.{ .scan_dir = id }, .instant) != 0) {
                self.worktree.scanner_thread.wakeup.notify() catch {};
            }

            // Queue monitor watcher (by id)
            if (self.worktree.monitor_thread.mailbox.push(.{ .add = id }, .instant) != 0) {
                self.worktree.monitor_thread.wakeup.notify() catch {};
            }
        }
    }
}

/// Stores path + entry info for diffing (path is arena-owned, just a reference)
const ChildInfo = struct {
    path: []const u8,
    entry: Entry,
};

pub fn process_events(self: *Scanner, fs_events: *std.AutoHashMap(u64, u32)) !*UpdatedEntriesSet {
    const result = try self.alloc.create(UpdatedEntriesSet);
    result.* = UpdatedEntriesSet.init(self.alloc);
    errdefer result.destroy();

    var it = fs_events.iterator();
    while (it.next()) |event| {
        const id = event.key_ptr.*;

        // Get path from snapshot
        const dir_path = blk: {
            self.snapshot.mutex.lock();
            defer self.snapshot.mutex.unlock();
            break :blk self.snapshot.getPathById(id) orelse continue;
        };

        // Build abs path on stack
        var abs_buf: [std.fs.max_path_bytes]u8 = undefined;
        const abs_dir_path = try self.buildAbsPath(dir_path, &abs_buf);

        try self.diffDirectory(dir_path, abs_dir_path, result);
    }

    return result;
}

fn diffDirectory(self: *Scanner, dir_path: []const u8, abs_dir_path: []const u8, result: *UpdatedEntriesSet) !void {
    // Use ChildInfo to store path reference + entry
    var current_children = std.AutoHashMap(u64, ChildInfo).init(self.alloc);
    defer current_children.deinit();

    // Collect current children from snapshot using range iterator
    // Range starts at "dir_path/" (first possible child) and we stop when prefix no longer matches
    {
        self.snapshot.mutex.lock();
        defer self.snapshot.mutex.unlock();

        // Build the prefix for children: "dir_path/"
        var prefix_buf: [std.fs.max_path_bytes]u8 = undefined;
        const prefix = std.fmt.bufPrint(&prefix_buf, "{s}/", .{dir_path}) catch return;

        // Use rangeFrom to start at first entry >= prefix
        var entries_it = self.snapshot.entries.rangeFrom(prefix);
        while (entries_it.next()) |entry| {
            const entry_path = entry.key;

            // Stop if we've moved past entries that start with our prefix
            if (!std.mem.startsWith(u8, entry_path, prefix)) {
                break;
            }

            // Check if this is a direct child (no more slashes after prefix)
            const rest = entry_path[prefix.len..];
            if (std.mem.indexOf(u8, rest, "/") == null) {
                try current_children.put(entry.value.id, .{
                    .path = entry_path,
                    .entry = entry.value,
                });
            }
        }
    }

    // Scan the actual directory
    var dir = std.fs.openDirAbsolute(abs_dir_path, .{ .iterate = true }) catch |err| {
        // Directory might have been deleted
        if (err == error.FileNotFound) {
            // Mark all current children as deleted - need to copy paths for cross-thread
            var children_it = current_children.valueIterator();
            while (children_it.next()) |child| {
                const deleted_path = try self.alloc.dupe(u8, child.path);
                try result.deleteEntry(child.entry.id, deleted_path);
            }
        }
        return;
    };
    defer dir.close();

    // Track which entries we've seen by building temp path and looking up
    var seen_ids = std.AutoHashMap(u64, void).init(self.alloc);
    defer seen_ids.deinit();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        const kind: Kind = switch (entry.kind) {
            .directory => .dir,
            .file => .file,
            else => continue,
        };

        // Look up if this child exists in snapshot
        const existing_id: ?u64 = blk: {
            self.snapshot.mutex.lock();
            defer self.snapshot.mutex.unlock();

            // Build child path to check
            const child_path = try self.snapshot.internPath(dir_path, entry.name);
            if (self.snapshot.entries.get(child_path) catch null) |existing| {
                break :blk existing.id;
            }
            // Path was interned but entry doesn't exist - that's fine, arena owns it
            break :blk null;
        };

        if (existing_id) |id| {
            try seen_ids.put(id, {});
            if (current_children.get(id)) |child_info| {
                // Entry exists - check if kind changed
                if (child_info.entry.kind != kind) {
                    try result.updateEntry(id, kind);
                }
            }
        } else {
            // New entry - intern and insert
            self.snapshot.mutex.lock();
            defer self.snapshot.mutex.unlock();

            const id = self.snapshot.newId();
            const interned_path = try self.snapshot.internPath(dir_path, entry.name);
            try self.snapshot.insertInterned(id, interned_path, kind);
            try result.addEntry(id, kind);

            // If directory, queue for scanning and monitoring
            if (kind == .dir) {
                if (self.worktree.scanner_thread.mailbox.push(.{ .scan_dir = id }, .instant) != 0) {
                    self.worktree.scanner_thread.wakeup.notify() catch {};
                }
                if (self.worktree.monitor_thread.mailbox.push(.{ .add = id }, .instant) != 0) {
                    self.worktree.monitor_thread.wakeup.notify() catch {};
                }
            }
        }
    }

    // Remaining entries in current_children that weren't seen were deleted
    var remaining_it = current_children.iterator();
    while (remaining_it.next()) |kv| {
        if (!seen_ids.contains(kv.key_ptr.*)) {
            // Copy path for cross-thread (owned by UpdatedEntriesSet)
            const deleted_path = try self.alloc.dupe(u8, kv.value_ptr.path);
            try result.deleteEntry(kv.key_ptr.*, deleted_path);
        }
    }
}

pub fn initial_scan(self: *Scanner) !void {
    var dir = std.fs.openDirAbsolute(self.abs_root, .{}) catch |err| {
        if (err == error.NotDir) {
            // It's a file, not a directory
            const id = self.snapshot.newId();
            self.snapshot.mutex.lock();
            defer self.snapshot.mutex.unlock();

            const root_path = try self.snapshot.internPathSingle(self.root_name);
            try self.snapshot.insertInterned(id, root_path, .file);
            return;
        }
        return err;
    };
    dir.close();

    // It's a directory
    const id = self.snapshot.newId();
    {
        self.snapshot.mutex.lock();
        defer self.snapshot.mutex.unlock();

        // Root entry uses the directory basename (e.g., "ares")
        const root_path = try self.snapshot.internPathSingle(self.root_name);
        try self.snapshot.insertInterned(id, root_path, .dir);

        try self.snapshot.entries.print();
    }

    // Queue scan for root directory (by id)
    if (self.worktree.scanner_thread.mailbox.push(.{ .scan_dir = id }, .instant) != 0) {
        self.worktree.scanner_thread.wakeup.notify() catch {};
    }

    // Queue monitor watcher for root (by id)
    if (self.worktree.monitor_thread.mailbox.push(.{ .add = id }, .instant) != 0) {
        self.worktree.monitor_thread.wakeup.notify() catch {};
    }
}
