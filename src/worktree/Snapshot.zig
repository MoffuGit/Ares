const std = @import("std");
const Allocator = std.mem.Allocator;
const worktreepkg = @import("mod.zig");
const Entries = worktreepkg.Entries;
const Kind = worktreepkg.Kind;
const FileType = worktreepkg.FileType;
const Stat = worktreepkg.Stat;

pub const Snapshot = @This();

mutex: std.Thread.Mutex = .{},
alloc: Allocator,
arena: std.heap.ArenaAllocator,
version: std.atomic.Value(u64) = .{ .raw = 0 },
next_id: std.atomic.Value(u64) = .{ .raw = 1 },

entries: Entries,
id_to_path: std.AutoHashMap(u64, []const u8),
id_to_abs_path: std.AutoHashMap(u64, []const u8),

pub fn init(alloc: Allocator) !Snapshot {
    const entries = try Entries.init(alloc);
    const arena = std.heap.ArenaAllocator.init(alloc);

    return .{
        .alloc = alloc,
        .arena = arena,
        .entries = entries,
        .id_to_path = std.AutoHashMap(u64, []const u8).init(alloc),
        .id_to_abs_path = std.AutoHashMap(u64, []const u8).init(alloc),
    };
}

pub fn deinit(self: *Snapshot) void {
    self.entries.deinit();
    self.id_to_path.deinit();
    self.id_to_abs_path.deinit();
    self.arena.deinit();
}

pub fn newId(self: *Snapshot) u64 {
    return self.next_id.fetchAdd(1, .monotonic);
}

/// Interns a path into the arena. The returned slice is valid for the lifetime of the Snapshot.
pub fn internPath(self: *Snapshot, parent: []const u8, name: []const u8) ![]const u8 {
    const arena_alloc = self.arena.allocator();
    if (parent.len == 0) {
        return try arena_alloc.dupe(u8, name);
    }
    const path = try arena_alloc.alloc(u8, parent.len + 1 + name.len);
    @memcpy(path[0..parent.len], parent);
    path[parent.len] = '/';
    @memcpy(path[parent.len + 1 ..], name);
    return path;
}

/// Interns a standalone path into the arena.
pub fn internPathSingle(self: *Snapshot, path: []const u8) ![]const u8 {
    return try self.arena.allocator().dupe(u8, path);
}

/// Insert an entry with an already-interned path (from internPath/internPathSingle).
pub fn insertInterned(self: *Snapshot, id: u64, path: []const u8, abs_path: []const u8, kind: Kind, file_type: FileType, stat: Stat) !void {
    try self.entries.insert(path, .{ .id = id, .kind = kind, .file_type = file_type, .stat = stat });
    try self.id_to_path.put(id, path);
    const interned_abs = try self.arena.allocator().dupe(u8, abs_path);
    try self.id_to_abs_path.put(id, interned_abs);
}

/// Insert with locking - path must already be interned.
pub fn insertInternedLocked(self: *Snapshot, id: u64, path: []const u8, abs_path: []const u8, kind: Kind, file_type: FileType, stat: Stat) !void {
    self.mutex.lock();
    defer self.mutex.unlock();
    try self.insertInterned(id, path, abs_path, kind, file_type, stat);
}

/// Remove an entry by path. Returns the entry if found.
pub fn remove(self: *Snapshot, path: []const u8) !?worktreepkg.Entry {
    const entry = self.entries.remove(path) catch return null;
    _ = self.id_to_path.remove(entry.id);
    _ = self.id_to_abs_path.remove(entry.id);
    return entry;
}

/// Get path by id (returns arena-owned slice, valid for Snapshot lifetime).
pub fn getPathById(self: *Snapshot, id: u64) ?[]const u8 {
    return self.id_to_path.get(id);
}

/// Get absolute path by id (returns arena-owned slice, valid for Snapshot lifetime).
pub fn getAbsPathById(self: *Snapshot, id: u64) ?[]const u8 {
    return self.id_to_abs_path.get(id);
}
