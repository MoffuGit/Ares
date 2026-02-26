const std = @import("std");
const fs = std.fs;
const builtin = @import("builtin");
const fmt = std.fmt;
const worktreepkg = @import("../mod.zig");

const Allocator = std.mem.Allocator;

const Monitor = @import("../../monitor/mod.zig");
const Snapshot = @import("../Snapshot.zig");
const Entry = Snapshot.Entry;
const Kind = Snapshot.Kind;
const FileType = Snapshot.FileType;
const Stat = Snapshot.Stat;

pub const Scanner = @This();

alloc: Allocator,

abs_root: []const u8,
root_name: []const u8,
snapshot: *Snapshot,
monitor: *Monitor,

mutex: std.Thread.Mutex = .{},
watcher_to_entry: std.AutoHashMap(u64, u64),
dirty_entries: std.ArrayList(u64) = .{},

pub fn init(alloc: Allocator, monitor: *Monitor, snapshot: *Snapshot, abs_root: []const u8) !Scanner {
    return .{
        .alloc = alloc,
        .monitor = monitor,
        .abs_root = abs_root,
        .root_name = std.fs.path.basename(abs_root),
        .snapshot = snapshot,
        .watcher_to_entry = std.AutoHashMap(u64, u64).init(alloc),
    };
}

pub fn deinit(self: *Scanner) void {
    self.watcher_to_entry.deinit();
    self.dirty_entries.deinit(self.alloc);
}

fn monitorCallback(self: ?*Scanner, watcher_id: u64, _: u32) void {
    const s = self.?;
    s.mutex.lock();
    defer s.mutex.unlock();
    const entry_id = s.watcher_to_entry.get(watcher_id) orelse return;
    s.dirty_entries.append(s.alloc, entry_id) catch return;
}
fn buildAbsPath(self: *Scanner, rel_path: []const u8, buf: []u8) ![]const u8 {
    if (std.mem.eql(u8, rel_path, self.root_name)) {
        return self.abs_root;
    }

    if (std.mem.startsWith(u8, rel_path, self.root_name) and rel_path.len > self.root_name.len and rel_path[self.root_name.len] == '/') {
        const suffix = rel_path[self.root_name.len..]; // includes leading "/"
        return try std.fmt.bufPrint(buf, "{s}{s}", .{ self.abs_root, suffix });
    }

    return try std.fmt.bufPrint(buf, "{s}/{s}", .{ self.abs_root, rel_path });
}

pub fn initial_scan(self: *Scanner) !void {
    const root_stat = self.getRootStat() catch Stat{};

    var dir = std.fs.openDirAbsolute(self.abs_root, .{}) catch |err| {
        if (err == error.NotDir) {
            const id = self.snapshot.newId();
            self.snapshot.mutex.lock();
            defer self.snapshot.mutex.unlock();

            const root_path = try self.snapshot.internPathSingle(self.root_name);
            const root_abs = try self.snapshot.internPathSingle(self.abs_root);
            try self.snapshot.insertInterned(id, root_path, root_abs, .file, FileType.fromName(self.root_name), root_stat);
            return;
        }
        return err;
    };
    dir.close();

    const id = self.snapshot.newId();
    {
        self.snapshot.mutex.lock();
        defer self.snapshot.mutex.unlock();

        const root_path = try self.snapshot.internPathSingle(self.root_name);
        const root_abs = try self.snapshot.internPathSingle(self.abs_root);
        try self.snapshot.insertInterned(id, root_path, root_abs, .dir, .unknown, root_stat);
    }

    try self.scanRecursive(id);

    if (!builtin.is_test) {
        const watcher_id = try self.monitor.watchPath(self.abs_root, Scanner, self, monitorCallback);
        try self.watcher_to_entry.put(watcher_id, id);
    }

    //NOTE: notify scan
    // const result = try self.alloc.create(UpdatedEntriesSet);
    // result.* = UpdatedEntriesSet.init(self.alloc);
    // if (!self.worktree.notifyUpdatedEntries(result)) {
    //     result.destroy();
    // }
}

pub fn process_scan_by_id(self: *Scanner, dir_id: u64) !void {
    try self.scanRecursive(dir_id);

    //NOTE:
    //notify we finish our scan
}

fn scanRecursive(self: *Scanner, dir_id: u64) !void {
    const rel_path = blk: {
        self.snapshot.mutex.lock();
        defer self.snapshot.mutex.unlock();
        break :blk self.snapshot.getPathById(dir_id) orelse return;
    };

    var abs_buf: [std.fs.max_path_bytes]u8 = undefined;
    const abs_path = try self.buildAbsPath(rel_path, &abs_buf);

    var child_dirs: std.ArrayList(u64) = .{};
    defer child_dirs.deinit(self.alloc);

    {
        var d = try std.fs.openDirAbsolute(abs_path, .{ .iterate = true });
        defer d.close();

        var iter = d.iterate();
        while (try iter.next()) |entry| {
            const kind: Kind = switch (entry.kind) {
                .directory => .dir,
                .file => .file,
                else => continue,
            };

            const stat = self.getEntryStat(d, entry.name) catch Stat{};
            const file_type: FileType = if (kind == .file) FileType.fromName(entry.name) else .unknown;
            const child_id = self.snapshot.newId();

            {
                self.snapshot.mutex.lock();
                defer self.snapshot.mutex.unlock();

                const interned = try self.snapshot.internPath(rel_path, entry.name);
                const interned_abs = try self.snapshot.internPath(abs_path, entry.name);
                try self.snapshot.insertInterned(child_id, interned, interned_abs, kind, file_type, stat);
            }

            if (kind == .dir) {
                try child_dirs.append(self.alloc, child_id);

                const child_abs = blk: {
                    self.snapshot.mutex.lock();
                    defer self.snapshot.mutex.unlock();
                    break :blk self.snapshot.getAbsPathById(child_id) orelse continue;
                };
                if (!builtin.is_test) {
                    const watcher_id = try self.monitor.watchPath(child_abs, Scanner, self, monitorCallback);
                    try self.watcher_to_entry.put(watcher_id, child_id);
                }
            }
        }
    }

    for (child_dirs.items) |child_id| {
        try self.scanRecursive(child_id);
    }
}

fn getEntryStat(_: *Scanner, dir: std.fs.Dir, name: []const u8) !Stat {
    const stat = try dir.statFile(name);
    return .{
        .size = stat.size,
        .mtime = stat.mtime,
        .atime = stat.atime,
        .ctime = stat.ctime,
        .mode = @intCast(stat.mode),
    };
}

const ChildInfo = struct {
    path: []const u8,
    entry: Entry,
};

pub fn process_events(self: *Scanner, dirty_ids: []const u64) !*UpdatedEntriesSet {
    const result = try self.alloc.create(UpdatedEntriesSet);
    result.* = UpdatedEntriesSet.init(self.alloc);
    errdefer result.destroy();

    for (dirty_ids) |id| {
        const dir_path = blk: {
            self.snapshot.mutex.lock();
            defer self.snapshot.mutex.unlock();
            break :blk self.snapshot.getPathById(id) orelse continue;
        };

        const abs_dir_path = blk: {
            self.snapshot.mutex.lock();
            defer self.snapshot.mutex.unlock();
            break :blk self.snapshot.getAbsPathById(id) orelse continue;
        };

        try self.update_entries(dir_path, abs_dir_path, result);
    }

    return result;
}

fn update_entries(self: *Scanner, dir_path: []const u8, abs_dir_path: []const u8, result: *UpdatedEntriesSet) !void {
    var current_children = std.AutoHashMap(u64, ChildInfo).init(self.alloc);
    defer current_children.deinit();

    {
        self.snapshot.mutex.lock();
        defer self.snapshot.mutex.unlock();

        var prefix_buf: [std.fs.max_path_bytes]u8 = undefined;
        const prefix = std.fmt.bufPrint(&prefix_buf, "{s}/", .{dir_path}) catch return;

        var entries_it = self.snapshot.entries.rangeFrom(prefix);
        while (entries_it.next()) |entry| {
            const entry_path = entry.key;

            if (!std.mem.startsWith(u8, entry_path, prefix)) {
                break;
            }

            const rest = entry_path[prefix.len..];
            if (std.mem.indexOf(u8, rest, "/") == null) {
                try current_children.put(entry.value.id, .{
                    .path = entry_path,
                    .entry = entry.value,
                });
            }
        }
    }

    var dir = std.fs.openDirAbsolute(abs_dir_path, .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) {
            var children_it = current_children.valueIterator();
            while (children_it.next()) |child| {
                const deleted_path = try self.alloc.dupe(u8, child.path);
                try result.deleteEntry(child.entry.id, deleted_path);

                self.snapshot.mutex.lock();
                defer self.snapshot.mutex.unlock();
                _ = self.snapshot.remove(deleted_path);
            }
        }
        return;
    };
    defer dir.close();

    var seen_ids = std.AutoHashMap(u64, void).init(self.alloc);
    defer seen_ids.deinit();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        const kind: Kind = switch (entry.kind) {
            .directory => .dir,
            .file => .file,
            else => continue,
        };

        const existing_id: ?u64 = blk: {
            self.snapshot.mutex.lock();
            defer self.snapshot.mutex.unlock();

            const child_path = try self.snapshot.internPath(dir_path, entry.name);
            if (self.snapshot.entries.get(child_path) catch null) |existing| {
                break :blk existing.id;
            }
            break :blk null;
        };

        if (existing_id) |id| {
            try seen_ids.put(id, {});
            if (current_children.get(id)) |child_info| {
                const stat = self.getEntryStat(dir, entry.name) catch Stat{};
                const kind_changed = child_info.entry.kind != kind;
                const stat_changed = child_info.entry.stat.size != stat.size or
                    child_info.entry.stat.mtime != stat.mtime or
                    child_info.entry.stat.mode != stat.mode;

                if (kind_changed or stat_changed) {
                    try result.updateEntry(id, kind);

                    self.snapshot.mutex.lock();
                    defer self.snapshot.mutex.unlock();
                    const child_path = self.snapshot.getPathById(id) orelse continue;
                    if (self.snapshot.entries.get_ref(child_path) catch null) |entry_ref| {
                        entry_ref.kind = kind;
                        entry_ref.stat = stat;
                    }
                }
            }
        } else {
            const stat = self.getEntryStat(dir, entry.name) catch Stat{};
            const file_type: FileType = if (kind == .file) FileType.fromName(entry.name) else .unknown;

            const id = self.snapshot.newId();
            {
                self.snapshot.mutex.lock();
                defer self.snapshot.mutex.unlock();

                const interned_path = try self.snapshot.internPath(dir_path, entry.name);
                const interned_abs = try self.snapshot.internPath(abs_dir_path, entry.name);
                try self.snapshot.insertInterned(id, interned_path, interned_abs, kind, file_type, stat);
            }
            try result.addEntry(id, kind);

            if (kind == .dir) {
                const child_abs = blk: {
                    self.snapshot.mutex.lock();
                    defer self.snapshot.mutex.unlock();
                    break :blk self.snapshot.getAbsPathById(id) orelse continue;
                };
                if (!builtin.is_test) {
                    const watcher_id = try self.monitor.watchPath(child_abs, Scanner, self, monitorCallback);
                    try self.watcher_to_entry.put(watcher_id, id);
                }
                try self.scanRecursive(id);
            }
        }
    }

    var remaining_it = current_children.iterator();
    while (remaining_it.next()) |kv| {
        if (!seen_ids.contains(kv.key_ptr.*)) {
            const deleted_path = try self.alloc.dupe(u8, kv.value_ptr.path);
            try result.deleteEntry(kv.key_ptr.*, deleted_path);

            self.snapshot.mutex.lock();
            defer self.snapshot.mutex.unlock();
            _ = self.snapshot.remove(deleted_path);
        }
    }
}
fn getRootStat(self: *Scanner) !Stat {
    const file = try std.fs.openFileAbsolute(self.abs_root, .{});
    defer file.close();
    const stat = try file.stat();
    return .{
        .size = stat.size,
        .mtime = stat.mtime,
        .atime = stat.atime,
        .ctime = stat.ctime,
        .mode = @intCast(stat.mode),
    };
}

pub const UpdatedEntriesSet = struct {
    pub const Update = union(enum) {
        add: struct { id: u64, kind: Kind },
        update: struct { id: u64, kind: Kind },
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

    pub fn deleteEntry(self: *UpdatedEntriesSet, id: u64, path: []const u8) !void {
        try self.updates.append(self.alloc, .{ .delete = .{ .id = id, .path = path } });
    }
};

test "scan single file" {
    const test_file_path = "test.txt";
    const testing = std.testing;
    const alloc = testing.allocator;
    const log = std.log;

    var file = try fs.cwd().createFile(test_file_path, .{});
    defer {
        file.close();
        fs.cwd().deleteFile(test_file_path) catch {};
    }

    const abs_path = try fs.cwd().realpathAlloc(alloc, test_file_path);
    defer alloc.free(abs_path);

    var snapshot = try Snapshot.init(alloc);
    defer snapshot.deinit();

    var scanner = try Scanner.init(alloc, undefined, &snapshot, abs_path);
    defer scanner.deinit();

    try scanner.initial_scan();

    var iter = snapshot.entries.iter();

    while (iter.next()) |entry| {
        log.err("key: {s}", .{entry.key});
    }
}
