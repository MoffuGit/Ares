const std = @import("std");
const fs = std.fs;
const builtin = @import("builtin");
const fmt = std.fmt;
const worktreepkg = @import("../mod.zig");
const global = @import("../../global.zig");

const Allocator = std.mem.Allocator;

const Monitor = @import("../../monitor/mod.zig");
const Snapshot = @import("../Snapshot.zig");
const Entry = Snapshot.Entry;
const Kind = Snapshot.Kind;
const fileTypeFromName = Snapshot.fileTypeFromName;
const Stat = Snapshot.Stat;

pub const Scanner = @This();

alloc: Allocator,

abs_root: []const u8,
root_name: []const u8,
snapshot: *Snapshot,
monitor: *Monitor,
stop_requested: std.atomic.Value(bool) = .{ .raw = false },

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

pub fn requestStop(self: *Scanner) void {
    self.stop_requested.store(true, .release);
}

pub fn isStopRequested(self: *Scanner) bool {
    return self.stop_requested.load(.acquire);
}

fn ensureRunning(self: *Scanner) !void {
    if (self.isStopRequested()) {
        return error.StopRequested;
    }
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
    try self.ensureRunning();
    const root_stat = self.getRootStat() catch Stat{};

    var dir = std.fs.openDirAbsolute(self.abs_root, .{}) catch |err| {
        if (err == error.NotDir) {
            const id = self.snapshot.newId();
            self.snapshot.rwlock.lock();
            defer self.snapshot.rwlock.unlock();

            const root_path = try self.snapshot.internPathSingle(self.root_name);
            const root_abs = try self.snapshot.internPathSingle(self.abs_root);
            try self.snapshot.insertInterned(id, root_path, root_abs, .file, fileTypeFromName(self.root_name), root_stat);
            return;
        }
        return err;
    };
    dir.close();

    const id = self.snapshot.newId();
    {
        self.snapshot.rwlock.lock();
        defer self.snapshot.rwlock.unlock();

        const root_path = try self.snapshot.internPathSingle(self.root_name);
        const root_abs = try self.snapshot.internPathSingle(self.abs_root);
        try self.snapshot.insertInterned(id, root_path, root_abs, .dir, "unknown", root_stat);
    }

    var count: usize = 0;

    try self.scanRecursive(id, &count);

    // if (!builtin.is_test) {
    //     const watcher_id = self.monitor.watchPath(self.abs_root, Scanner, self, monitorCallback) catch null;
    //     if (watcher_id) |_id| {
    //         try self.watcher_to_entry.put(_id, id);
    //     }
    // }

    var update = UpdatedEntriesSet.init(self.alloc);
    defer update.deinit();

    global.state.emitGlobal(.{ .worktreeUpdate = update });
}

pub fn process_scan_by_id(self: *Scanner, id: u64) !void {
    try self.ensureRunning();
    var count: usize = 0;
    try self.scanRecursive(id, &count);
}

fn scanRecursive(self: *Scanner, dir_id: u64, count: *usize) !void {
    try self.ensureRunning();

    const rel_path = blk: {
        self.snapshot.rwlock.lockShared();
        defer self.snapshot.rwlock.unlockShared();
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
            try self.ensureRunning();

            const kind: Kind = switch (entry.kind) {
                .directory => .dir,
                .file => .file,
                else => continue,
            };

            const stat = self.getEntryStat(d, entry.name) catch Stat{};
            const file_type = if (kind == .file) fileTypeFromName(entry.name) else "unknown";
            const child_id = self.snapshot.newId();

            {
                self.snapshot.rwlock.lock();
                defer self.snapshot.rwlock.unlock();

                const interned = try self.snapshot.internPath(rel_path, entry.name);
                const interned_abs = try self.snapshot.internPath(abs_path, entry.name);
                try self.snapshot.insertInterned(child_id, interned, interned_abs, kind, file_type, stat);
            }

            if (kind == .dir) {
                try child_dirs.append(self.alloc, child_id);

                const child_abs = blk: {
                    self.snapshot.rwlock.lockShared();
                    defer self.snapshot.rwlock.unlockShared();
                    break :blk self.snapshot.getAbsPathById(child_id) orelse continue;
                };
                _ = child_abs;
                // if (!builtin.is_test) {
                //     const watcher_id = self.monitor.watchPath(child_abs, Scanner, self, monitorCallback) catch null;
                //     if (watcher_id) |id| {
                //         try self.watcher_to_entry.put(id, child_id);
                //     }
                // }
            }
        }
    }

    if (count.* > 1000) {
        count.* = 0;
        var update = UpdatedEntriesSet.init(self.alloc);
        defer update.deinit();

        global.state.emitGlobal(.{ .worktreeUpdate = update });
    } else {
        count.* += 1;
    }

    for (child_dirs.items) |child_id| {
        try self.ensureRunning();
        try self.scanRecursive(child_id, count);
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

pub fn process_events(self: *Scanner, dirty_ids: []const u64) !UpdatedEntriesSet {
    try self.ensureRunning();

    var result = UpdatedEntriesSet.init(self.alloc);

    for (dirty_ids) |id| {
        try self.ensureRunning();

        const dir_path = blk: {
            self.snapshot.rwlock.lockShared();
            defer self.snapshot.rwlock.unlockShared();
            break :blk self.snapshot.getPathById(id) orelse continue;
        };

        const abs_dir_path = blk: {
            self.snapshot.rwlock.lockShared();
            defer self.snapshot.rwlock.unlockShared();
            break :blk self.snapshot.getAbsPathById(id) orelse continue;
        };

        try self.update_entries(dir_path, abs_dir_path, &result);
    }

    return result;
}

fn update_entries(self: *Scanner, dir_path: []const u8, abs_dir_path: []const u8, result: *UpdatedEntriesSet) !void {
    try self.ensureRunning();

    var current_children = std.AutoHashMap(u64, ChildInfo).init(self.alloc);
    defer current_children.deinit();

    {
        self.snapshot.rwlock.lockShared();
        defer self.snapshot.rwlock.unlockShared();

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

                self.snapshot.rwlock.lock();
                defer self.snapshot.rwlock.unlock();
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
        try self.ensureRunning();

        const kind: Kind = switch (entry.kind) {
            .directory => .dir,
            .file => .file,
            else => continue,
        };

        const existing_id: ?u64 = blk: {
            self.snapshot.rwlock.lock();
            defer self.snapshot.rwlock.unlock();

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

                    self.snapshot.rwlock.lock();
                    defer self.snapshot.rwlock.unlock();
                    const child_path = self.snapshot.getPathById(id) orelse continue;
                    if (self.snapshot.entries.get_ref(child_path) catch null) |entry_ref| {
                        entry_ref.kind = kind;
                        entry_ref.stat = stat;
                    }
                }
            }
        } else {
            const stat = self.getEntryStat(dir, entry.name) catch Stat{};
            const file_type = if (kind == .file) fileTypeFromName(entry.name) else "unknown";

            const id = self.snapshot.newId();
            {
                self.snapshot.rwlock.lock();
                defer self.snapshot.rwlock.unlock();

                const interned_path = try self.snapshot.internPath(dir_path, entry.name);
                const interned_abs = try self.snapshot.internPath(abs_dir_path, entry.name);
                try self.snapshot.insertInterned(id, interned_path, interned_abs, kind, file_type, stat);
            }
            try result.addEntry(id, kind);

            if (kind == .dir) {
                const child_abs = blk: {
                    self.snapshot.rwlock.lockShared();
                    defer self.snapshot.rwlock.unlockShared();
                    break :blk self.snapshot.getAbsPathById(id) orelse continue;
                };
                _ = child_abs;
                // if (!builtin.is_test) {
                //     const watcher_id = try self.monitor.watchPath(child_abs, Scanner, self, monitorCallback);
                //     try self.watcher_to_entry.put(watcher_id, id);
                // }

                var count: usize = 0;

                try self.scanRecursive(id, &count);
            }
        }
    }

    var remaining_it = current_children.iterator();
    while (remaining_it.next()) |kv| {
        if (!seen_ids.contains(kv.key_ptr.*)) {
            const deleted_path = try self.alloc.dupe(u8, kv.value_ptr.path);
            try result.deleteEntry(kv.key_ptr.*, deleted_path);

            self.snapshot.rwlock.lock();
            defer self.snapshot.rwlock.unlock();
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

const testing = std.testing;

fn testInit(alloc: Allocator, snapshot: *Snapshot, abs_path: []const u8) !Scanner {
    return Scanner.init(alloc, undefined, snapshot, abs_path);
}

test "initial_scan single file" {
    const alloc = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    (try tmp.dir.createFile("test.zig", .{})).close();

    const abs_file = try tmp.dir.realpathAlloc(alloc, "test.zig");
    defer alloc.free(abs_file);

    var snapshot = try Snapshot.init(alloc);
    defer snapshot.deinit();

    var scanner = try testInit(alloc, &snapshot, abs_file);
    defer scanner.deinit();

    try scanner.initial_scan();

    try testing.expectEqual(@as(usize, 1), snapshot.id_to_path.count());
    const entry = try snapshot.entries.get("test.zig");
    try testing.expectEqual(Kind.file, entry.kind);
    try testing.expectEqualStrings("zig", entry.file_type);
}

test "initial_scan directory contents" {
    const alloc = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    (try tmp.dir.createFile("hello.zig", .{})).close();
    (try tmp.dir.createFile("world.txt", .{})).close();

    var path_buf: [fs.max_path_bytes]u8 = undefined;
    const abs_path = try tmp.dir.realpath(".", &path_buf);

    var snapshot = try Snapshot.init(alloc);
    defer snapshot.deinit();

    var scanner = try testInit(alloc, &snapshot, abs_path);
    defer scanner.deinit();

    try scanner.initial_scan();

    const root_name = fs.path.basename(abs_path);

    const root = try snapshot.entries.get(root_name);
    try testing.expectEqual(Kind.dir, root.kind);

    var buf1: [fs.max_path_bytes]u8 = undefined;
    const zig_path = try fmt.bufPrint(&buf1, "{s}/hello.zig", .{root_name});
    const zig_entry = try snapshot.entries.get(zig_path);
    try testing.expectEqual(Kind.file, zig_entry.kind);
    try testing.expectEqualStrings("zig", zig_entry.file_type);

    var buf2: [fs.max_path_bytes]u8 = undefined;
    const txt_path = try fmt.bufPrint(&buf2, "{s}/world.txt", .{root_name});
    const txt_entry = try snapshot.entries.get(txt_path);
    try testing.expectEqual(Kind.file, txt_entry.kind);
    try testing.expectEqualStrings("txt", txt_entry.file_type);

    try testing.expectEqual(@as(usize, 3), snapshot.id_to_path.count());
}

test "initial_scan nested directories" {
    const alloc = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makeDir("sub");
    (try tmp.dir.createFile("sub/nested.go", .{})).close();
    try tmp.dir.makePath("sub/deep");
    (try tmp.dir.createFile("sub/deep/leaf.py", .{})).close();

    var path_buf: [fs.max_path_bytes]u8 = undefined;
    const abs_path = try tmp.dir.realpath(".", &path_buf);

    var snapshot = try Snapshot.init(alloc);
    defer snapshot.deinit();

    var scanner = try testInit(alloc, &snapshot, abs_path);
    defer scanner.deinit();

    try scanner.initial_scan();

    const root_name = fs.path.basename(abs_path);

    var buf1: [fs.max_path_bytes]u8 = undefined;
    const nested_path = try fmt.bufPrint(&buf1, "{s}/sub/nested.go", .{root_name});
    const nested = try snapshot.entries.get(nested_path);
    try testing.expectEqual(Kind.file, nested.kind);
    try testing.expectEqualStrings("go", nested.file_type);

    var buf2: [fs.max_path_bytes]u8 = undefined;
    const deep_path = try fmt.bufPrint(&buf2, "{s}/sub/deep/leaf.py", .{root_name});
    const deep = try snapshot.entries.get(deep_path);
    try testing.expectEqual(Kind.file, deep.kind);
    try testing.expectEqualStrings("py", deep.file_type);

    // root + sub + sub/deep + nested.go + leaf.py = 5
    try testing.expectEqual(@as(usize, 5), snapshot.id_to_path.count());
}
//
test "initial_scan populates stat" {
    const alloc = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    {
        const f = try tmp.dir.createFile("data.txt", .{});
        try f.writeAll("hello world");
        f.close();
    }

    var path_buf: [fs.max_path_bytes]u8 = undefined;
    const abs_path = try tmp.dir.realpath(".", &path_buf);

    var snapshot = try Snapshot.init(alloc);
    defer snapshot.deinit();

    var scanner = try testInit(alloc, &snapshot, abs_path);
    defer scanner.deinit();

    try scanner.initial_scan();

    const root_name = fs.path.basename(abs_path);
    var buf: [fs.max_path_bytes]u8 = undefined;
    const file_path = try fmt.bufPrint(&buf, "{s}/data.txt", .{root_name});
    const entry = try snapshot.entries.get(file_path);
    try testing.expectEqual(@as(u64, 11), entry.stat.size);
    try testing.expect(entry.stat.mtime != 0);
}
//
test "process_scan_by_id scans specific directory" {
    const alloc = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makeDir("target");
    (try tmp.dir.createFile("target/file.lua", .{})).close();

    var path_buf: [fs.max_path_bytes]u8 = undefined;
    const abs_path = try tmp.dir.realpath(".", &path_buf);

    var snapshot = try Snapshot.init(alloc);
    defer snapshot.deinit();

    var scanner = try testInit(alloc, &snapshot, abs_path);
    defer scanner.deinit();

    const root_name = fs.path.basename(abs_path);
    const dir_id = snapshot.newId();
    {
        snapshot.rwlock.lock();
        defer snapshot.rwlock.unlock();

        const dir_rel = try snapshot.internPath(root_name, "target");
        var abs_buf: [fs.max_path_bytes]u8 = undefined;
        const dir_abs = try snapshot.internPathSingle(try fmt.bufPrint(&abs_buf, "{s}/target", .{abs_path}));
        try snapshot.insertInterned(dir_id, dir_rel, dir_abs, .dir, "unknown", .{});
    }

    try scanner.process_scan_by_id(dir_id);

    var buf: [fs.max_path_bytes]u8 = undefined;
    const child_path = try fmt.bufPrint(&buf, "{s}/target/file.lua", .{root_name});
    const child = try snapshot.entries.get(child_path);
    try testing.expectEqual(Kind.file, child.kind);
    try testing.expectEqualStrings("lua", child.file_type);
}

test "process_events detects new files" {
    const alloc = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    (try tmp.dir.createFile("original.zig", .{})).close();

    var path_buf: [fs.max_path_bytes]u8 = undefined;
    const abs_path = try tmp.dir.realpath(".", &path_buf);

    var snapshot = try Snapshot.init(alloc);
    defer snapshot.deinit();

    var scanner = try testInit(alloc, &snapshot, abs_path);
    defer scanner.deinit();

    try scanner.initial_scan();

    const root_name = fs.path.basename(abs_path);
    const root = try snapshot.entries.get(root_name);
    const root_id = root.id;

    // Add a new file after initial scan
    (try tmp.dir.createFile("added.rs", .{})).close();

    var result = try scanner.process_events(&.{root_id});
    defer result.deinit();

    var found_add = false;
    for (result.updates.items) |update| {
        switch (update) {
            .add => |a| {
                if (a.kind == .file) found_add = true;
            },
            else => {},
        }
    }
    try testing.expect(found_add);

    // Verify the new file is in the snapshot
    var buf: [fs.max_path_bytes]u8 = undefined;
    const added_path = try fmt.bufPrint(&buf, "{s}/added.rs", .{root_name});
    const added = try snapshot.entries.get(added_path);
    try testing.expectEqual(Kind.file, added.kind);
    try testing.expectEqualStrings("rs", added.file_type);
}

test "process_events detects deleted files" {
    const alloc = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    (try tmp.dir.createFile("keep.zig", .{})).close();
    (try tmp.dir.createFile("remove.txt", .{})).close();

    var path_buf: [fs.max_path_bytes]u8 = undefined;
    const abs_path = try tmp.dir.realpath(".", &path_buf);

    var snapshot = try Snapshot.init(alloc);
    defer snapshot.deinit();

    var scanner = try testInit(alloc, &snapshot, abs_path);
    defer scanner.deinit();

    try scanner.initial_scan();

    const root_name = fs.path.basename(abs_path);
    const root = try snapshot.entries.get(root_name);

    // Delete the file
    try tmp.dir.deleteFile("remove.txt");

    var result = try scanner.process_events(&.{root.id});
    defer result.deinit();

    var found_delete = false;
    for (result.updates.items) |update| {
        switch (update) {
            .delete => {
                found_delete = true;
            },
            else => {},
        }
    }
    try testing.expect(found_delete);

    // Verify deleted file is gone from snapshot
    var buf: [fs.max_path_bytes]u8 = undefined;
    const removed_path = try fmt.bufPrint(&buf, "{s}/remove.txt", .{root_name});
    const removed = snapshot.entries.get(removed_path) catch null;
    try testing.expect(removed == null);
}

test "process_events detects modified files" {
    const alloc = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    {
        const f = try tmp.dir.createFile("data.txt", .{});
        try f.writeAll("short");
        f.close();
    }

    var path_buf: [fs.max_path_bytes]u8 = undefined;
    const abs_path = try tmp.dir.realpath(".", &path_buf);

    var snapshot = try Snapshot.init(alloc);
    defer snapshot.deinit();

    var scanner = try testInit(alloc, &snapshot, abs_path);
    defer scanner.deinit();

    try scanner.initial_scan();

    const root_name = fs.path.basename(abs_path);
    const root = try snapshot.entries.get(root_name);

    // Modify the file with different content size
    {
        const f = try tmp.dir.createFile("data.txt", .{ .truncate = true });
        try f.writeAll("much longer content here");
        f.close();
    }

    var result = try scanner.process_events(&.{root.id});
    defer result.deinit();

    var found_update = false;
    for (result.updates.items) |update| {
        switch (update) {
            .update => {
                found_update = true;
            },
            else => {},
        }
    }
    try testing.expect(found_update);
}

test "scanRecursive stops when stop requested" {
    const alloc = testing.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.makePath("sub/deep");
    (try tmp.dir.createFile("sub/deep/file.txt", .{})).close();

    var path_buf: [fs.max_path_bytes]u8 = undefined;
    const abs_path = try tmp.dir.realpath(".", &path_buf);

    var snapshot = try Snapshot.init(alloc);
    defer snapshot.deinit();

    var scanner = try testInit(alloc, &snapshot, abs_path);
    defer scanner.deinit();

    const root_name = fs.path.basename(abs_path);
    const root_id = snapshot.newId();
    {
        snapshot.rwlock.lock();
        defer snapshot.rwlock.unlock();

        const root_path = try snapshot.internPathSingle(root_name);
        const root_abs = try snapshot.internPathSingle(abs_path);
        try snapshot.insertInterned(root_id, root_path, root_abs, .dir, "unknown", .{});
    }

    scanner.requestStop();

    var count: usize = 0;
    try testing.expectError(error.StopRequested, scanner.scanRecursive(root_id, &count));
    try testing.expectEqual(@as(usize, 1), snapshot.id_to_path.count());
}
