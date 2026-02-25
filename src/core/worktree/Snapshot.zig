const std = @import("std");
const Allocator = std.mem.Allocator;
const BPlusTree = @import("datastruct").BPlusTree;

const Stat = @import("../io/mod.zig").Stat;

pub const Entries = BPlusTree([]const u8, Entry, entryOrder);
fn entryOrder(a: []const u8, b: []const u8) std.math.Order {
    return std.mem.order(u8, a, b);
}

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
pub fn remove(self: *Snapshot, path: []const u8) ?Entry {
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

/// Get an owned copy of the path by id. Caller owns the returned slice.
pub fn clonePathById(self: *Snapshot, alloc: Allocator, id: u64) ?[]const u8 {
    self.mutex.lock();
    defer self.mutex.unlock();
    const path = self.id_to_path.get(id) orelse return null;
    return alloc.dupe(u8, path) catch return null;
}

/// Get an owned copy of the absolute path by id. Caller owns the returned slice.
pub fn cloneAbsPathById(self: *Snapshot, alloc: Allocator, id: u64) ?[]const u8 {
    self.mutex.lock();
    defer self.mutex.unlock();
    const abs_path = self.id_to_abs_path.get(id) orelse return null;
    return alloc.dupe(u8, abs_path) catch return null;
}

/// Get a copy of an entry by id, with locking.
pub fn getEntryById(self: *Snapshot, id: u64) ?Entry {
    self.mutex.lock();
    defer self.mutex.unlock();
    const path = self.id_to_path.get(id) orelse return null;
    return self.entries.get(path) catch return null;
}

pub const Entry = struct {
    id: u64,
    kind: Kind,
    file_type: FileType = .unknown,
    stat: Stat = .{},
};

pub const Kind = enum { file, dir };

pub const FileType = enum {
    zig,
    c,
    cpp,
    h,
    py,
    js,
    ts,
    json,
    xml,
    yaml,
    toml,
    md,
    txt,
    html,
    css,
    sh,
    go,
    rs,
    java,
    rb,
    lua,
    makefile,
    dockerfile,
    gitignore,
    license,
    unknown,

    pub fn fromName(name: []const u8) FileType {
        if (std.mem.eql(u8, name, "Makefile") or std.mem.eql(u8, name, "makefile") or std.mem.eql(u8, name, "GNUmakefile")) return .makefile;
        if (std.mem.eql(u8, name, "Dockerfile") or std.mem.startsWith(u8, name, "Dockerfile.")) return .dockerfile;
        if (std.mem.eql(u8, name, ".gitignore")) return .gitignore;
        if (std.mem.eql(u8, name, "LICENSE") or std.mem.eql(u8, name, "LICENSE.md") or std.mem.eql(u8, name, "LICENSE.txt")) return .license;

        const ext = std.fs.path.extension(name);
        if (ext.len == 0) return .unknown;
        const e = ext[1..];

        if (std.mem.eql(u8, e, "zig")) return .zig;
        if (std.mem.eql(u8, e, "c")) return .c;
        if (std.mem.eql(u8, e, "cpp") or std.mem.eql(u8, e, "cc") or std.mem.eql(u8, e, "cxx")) return .cpp;
        if (std.mem.eql(u8, e, "h") or std.mem.eql(u8, e, "hpp") or std.mem.eql(u8, e, "hxx")) return .h;
        if (std.mem.eql(u8, e, "py")) return .py;
        if (std.mem.eql(u8, e, "js") or std.mem.eql(u8, e, "mjs") or std.mem.eql(u8, e, "cjs")) return .js;
        if (std.mem.eql(u8, e, "ts") or std.mem.eql(u8, e, "mts") or std.mem.eql(u8, e, "cts")) return .ts;
        if (std.mem.eql(u8, e, "json")) return .json;
        if (std.mem.eql(u8, e, "xml")) return .xml;
        if (std.mem.eql(u8, e, "yaml") or std.mem.eql(u8, e, "yml")) return .yaml;
        if (std.mem.eql(u8, e, "toml")) return .toml;
        if (std.mem.eql(u8, e, "md") or std.mem.eql(u8, e, "markdown")) return .md;
        if (std.mem.eql(u8, e, "txt")) return .txt;
        if (std.mem.eql(u8, e, "html") or std.mem.eql(u8, e, "htm")) return .html;
        if (std.mem.eql(u8, e, "css")) return .css;
        if (std.mem.eql(u8, e, "sh") or std.mem.eql(u8, e, "bash") or std.mem.eql(u8, e, "zsh")) return .sh;
        if (std.mem.eql(u8, e, "go")) return .go;
        if (std.mem.eql(u8, e, "rs")) return .rs;
        if (std.mem.eql(u8, e, "java")) return .java;
        if (std.mem.eql(u8, e, "rb")) return .rb;
        if (std.mem.eql(u8, e, "lua")) return .lua;
        return .unknown;
    }

    pub fn toString(self: FileType) []const u8 {
        return switch (self) {
            .zig => "zig",
            .c => "c",
            .cpp => "cpp",
            .h => "h",
            .py => "py",
            .js => "js",
            .ts => "ts",
            .json => "json",
            .xml => "xml",
            .yaml => "yaml",
            .toml => "toml",
            .md => "md",
            .txt => "txt",
            .html => "html",
            .css => "css",
            .sh => "sh",
            .go => "go",
            .rs => "rs",
            .java => "java",
            .rb => "rb",
            .lua => "lua",
            .makefile => "makefile",
            .dockerfile => "dockerfile",
            .gitignore => "gitignore",
            .license => "license",
            .unknown => "unknown",
        };
    }
};
