const std = @import("std");
const Allocator = std.mem.Allocator;
const BPlusTree = @import("datastruct").BPlusTree;

pub const Stat = @import("../io/mod.zig").Stat;

pub const Entries = BPlusTree([]const u8, Entry, entryOrder);
fn entryOrder(a: []const u8, b: []const u8) std.math.Order {
    return std.mem.order(u8, a, b);
}

pub const Snapshot = @This();

rwlock: std.Thread.RwLock = .{},
alloc: Allocator,
arena: std.heap.ArenaAllocator,
version: std.atomic.Value(u64) = .{ .raw = 0 },
next_id: std.atomic.Value(u64) = .{ .raw = 1 },

entries: Entries,
id_to_path: std.AutoHashMap(u64, []const u8),
id_to_abs_path: std.AutoHashMap(u64, []const u8),
file_type_cache: std.StringHashMap([]const u8),

pub fn init(alloc: Allocator) !Snapshot {
    const entries = try Entries.init(alloc);
    const arena = std.heap.ArenaAllocator.init(alloc);

    return .{
        .alloc = alloc,
        .arena = arena,
        .entries = entries,
        .id_to_path = std.AutoHashMap(u64, []const u8).init(alloc),
        .id_to_abs_path = std.AutoHashMap(u64, []const u8).init(alloc),
        .file_type_cache = std.StringHashMap([]const u8).init(alloc),
    };
}

pub fn deinit(self: *Snapshot) void {
    self.entries.deinit();
    self.id_to_path.deinit();
    self.id_to_abs_path.deinit();
    self.file_type_cache.deinit();
    self.arena.deinit();
}

pub fn count(self: *Snapshot) usize {
    return self.entries.count;
}

pub fn newId(self: *Snapshot) u64 {
    return self.next_id.fetchAdd(1, .monotonic);
}

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

pub fn internPathSingle(self: *Snapshot, path: []const u8) ![]const u8 {
    return try self.arena.allocator().dupe(u8, path);
}

pub fn internFileType(self: *Snapshot, file_type: []const u8) ![]const u8 {
    if (self.file_type_cache.get(file_type)) |cached| return cached;
    const interned = try self.arena.allocator().dupe(u8, file_type);
    try self.file_type_cache.put(interned, interned);
    return interned;
}

pub fn insertInterned(self: *Snapshot, id: u64, path: []const u8, abs_path: []const u8, kind: Kind, file_type: []const u8, stat: Stat) !void {
    const interned_ft = try self.internFileType(file_type);
    try self.entries.insert(path, .{ .id = id, .kind = kind, .file_type = interned_ft, .stat = stat });
    try self.id_to_path.put(id, path);
    const interned_abs = try self.arena.allocator().dupe(u8, abs_path);
    try self.id_to_abs_path.put(id, interned_abs);
}

pub fn insertInternedLocked(self: *Snapshot, id: u64, path: []const u8, abs_path: []const u8, kind: Kind, file_type: []const u8, stat: Stat) !void {
    self.rwlock.lock();
    defer self.rwlock.unlock();
    try self.insertInterned(id, path, abs_path, kind, file_type, stat);
}

pub fn remove(self: *Snapshot, path: []const u8) ?Entry {
    const entry = self.entries.remove(path) catch return null;
    _ = self.id_to_path.remove(entry.id);
    _ = self.id_to_abs_path.remove(entry.id);
    return entry;
}

pub fn getPathById(self: *Snapshot, id: u64) ?[]const u8 {
    return self.id_to_path.get(id);
}

pub fn getAbsPathById(self: *Snapshot, id: u64) ?[]const u8 {
    return self.id_to_abs_path.get(id);
}

pub fn clonePathById(self: *Snapshot, alloc: Allocator, id: u64) ?[]const u8 {
    self.rwlock.lockShared();
    defer self.rwlock.unlockShared();
    const path = self.id_to_path.get(id) orelse return null;
    return alloc.dupe(u8, path) catch return null;
}

pub fn cloneAbsPathById(self: *Snapshot, alloc: Allocator, id: u64) ?[]const u8 {
    self.rwlock.lockShared();
    defer self.rwlock.unlockShared();
    const abs_path = self.id_to_abs_path.get(id) orelse return null;
    return alloc.dupe(u8, abs_path) catch return null;
}

pub fn getEntryById(self: *Snapshot, id: u64) ?Entry {
    self.rwlock.lockShared();
    defer self.rwlock.unlockShared();
    const path = self.id_to_path.get(id) orelse return null;
    return self.entries.get(path) catch return null;
}

pub const Entry = struct {
    id: u64,
    kind: Kind,
    file_type: []const u8 = "unknown",
    stat: Stat = .{},
};

pub const Kind = enum { file, dir };

pub fn fileTypeFromName(name: []const u8) []const u8 {
    if (std.mem.eql(u8, name, "Makefile") or std.mem.eql(u8, name, "makefile") or std.mem.eql(u8, name, "GNUmakefile")) return "makefile";
    if (std.mem.eql(u8, name, "Dockerfile") or std.mem.startsWith(u8, name, "Dockerfile.")) return "dockerfile";
    if (std.mem.eql(u8, name, ".gitignore")) return "gitignore";
    if (std.mem.eql(u8, name, "LICENSE") or std.mem.eql(u8, name, "LICENSE.md") or std.mem.eql(u8, name, "LICENSE.txt")) return "license";

    const ext = std.fs.path.extension(name);
    if (ext.len == 0) return "unknown";
    const e = ext[1..];

    //INFO:
    //lets try without this first
    // if (std.mem.eql(u8, e, "cc") or std.mem.eql(u8, e, "cxx")) return "cpp";
    // if (std.mem.eql(u8, e, "hpp") or std.mem.eql(u8, e, "hxx")) return "h";
    // if (std.mem.eql(u8, e, "mjs") or std.mem.eql(u8, e, "cjs")) return "js";
    // if (std.mem.eql(u8, e, "mts") or std.mem.eql(u8, e, "cts")) return "ts";
    // if (std.mem.eql(u8, e, "yml")) return "yaml";
    // if (std.mem.eql(u8, e, "markdown")) return "md";
    // if (std.mem.eql(u8, e, "htm")) return "html";
    // if (std.mem.eql(u8, e, "bash") or std.mem.eql(u8, e, "zsh")) return "sh";

    return e;
}
