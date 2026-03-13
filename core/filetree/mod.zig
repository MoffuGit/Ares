const std = @import("std");
const global = @import("../global.zig");

const worktreepkg = @import("../worktree/mod.zig");
const Worktree = worktreepkg.Worktree;
const Entry = worktreepkg.Entry;

const Allocator = std.mem.Allocator;

pub const FileTree = @This();

alloc: Allocator,
mutex: std.Thread.Mutex = .{},
expanded_entries: std.AutoHashMap(u64, void),
visible_entries: std.ArrayList(u64) = .{},
worktree: *Worktree,

listener: global.EventEmitter.Listener,

pub fn create(alloc: Allocator, worktree: *Worktree) !*FileTree {
    const self = try alloc.create(FileTree);
    errdefer alloc.destroy(self);

    var map = std.AutoHashMap(u64, void).init(alloc);
    errdefer map.deinit();

    self.* = .{
        .alloc = alloc,
        .expanded_entries = map,
        .worktree = worktree,
        .listener = .{
            .ctx = self,
            .handle = worktreeUpdateCallback,
        },
    };

    try global.state.events.on(.worktreeUpdate, self.listener);

    return self;
}

fn worktreeUpdateCallback(ctx: *anyopaque) void {
    const self: *FileTree = @ptrCast(@alignCast(ctx));
    self.mutex.lock();
    defer self.mutex.unlock();

    self.rebuildVisibleEntries();
}

pub fn destroy(self: *FileTree) void {
    global.state.events.off(.worktreeUpdate, self.listener);
    self.expanded_entries.deinit();
    self.visible_entries.deinit(self.alloc);
    self.alloc.destroy(self);
}

pub fn selectEntry(self: *FileTree, id: u64) void {
    const entry = entry: {
        self.worktree.snapshot.mutex.lock();
        defer self.worktree.snapshot.mutex.unlock();

        const path = self.worktree.snapshot.getPathById(id) orelse return;
        break :entry self.worktree.snapshot.entries.get(path) catch return;
    };

    if (entry.kind == .dir) {
        if (self.expanded_entries.contains(entry.id)) {
            _ = self.expanded_entries.remove(entry.id);
        } else {
            self.expanded_entries.put(entry.id, {}) catch {};
        }
        self.rebuildVisibleEntries();
    } else {}
}

fn rebuildVisibleEntries(self: *FileTree) void {
    self.visible_entries.clearRetainingCapacity();

    self.worktree.snapshot.mutex.lock();
    defer self.worktree.snapshot.mutex.unlock();

    var it = self.worktree.snapshot.entries.iter();
    while (it.next()) |entry| {
        if (std.mem.indexOfScalar(u8, entry.key, '/') != null) continue;

        self.visible_entries.append(self.alloc, entry.value.id) catch continue;

        if (entry.value.kind == .dir and self.expanded_entries.contains(entry.value.id)) {
            self.appendDirectChildren(entry.key);
        }
    }

    global.state.emit(.filetreeUpdate, .instant);
}

fn appendDirectChildren(self: *FileTree, dir_path: []const u8) void {
    var prefix_buf: [std.fs.max_path_bytes]u8 = undefined;
    const prefix = std.fmt.bufPrint(&prefix_buf, "{s}/", .{dir_path}) catch return;

    var dir_it = self.worktree.snapshot.entries.rangeFrom(prefix);
    while (dir_it.next()) |entry| {
        if (!std.mem.startsWith(u8, entry.key, prefix)) break;
        const rest = entry.key[prefix.len..];
        if (std.mem.indexOfScalar(u8, rest, '/') != null) continue;
        if (entry.value.kind != .dir) continue;
        self.visible_entries.append(self.alloc, entry.value.id) catch continue;

        if (self.expanded_entries.contains(entry.value.id)) {
            self.appendDirectChildren(entry.key);
        }
    }

    var file_it = self.worktree.snapshot.entries.rangeFrom(prefix);
    while (file_it.next()) |entry| {
        if (!std.mem.startsWith(u8, entry.key, prefix)) break;
        const rest = entry.key[prefix.len..];
        if (std.mem.indexOfScalar(u8, rest, '/') != null) continue;
        if (entry.value.kind != .file) continue;
        self.visible_entries.append(self.alloc, entry.value.id) catch continue;
    }
}
