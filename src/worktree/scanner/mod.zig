const std = @import("std");
const Allocator = std.mem.Allocator;
const worktreepkg = @import("../mod.zig");
const Worktree = worktreepkg.Worktree;
const Entry = worktreepkg.Entry;
const Kind = worktreepkg.Kind;
const Snapshot = @import("../Snapshot.zig");

pub const Scanner = @This();

alloc: Allocator,
worktree: *Worktree,

fd: i32,
abs_path: *[]u8,
root: *[]u8,
snapshot: *Snapshot,

pub fn init(alloc: Allocator, worktree: *Worktree) !Scanner {
    return .{ .alloc = alloc, .worktree = worktree, .abs_path = &worktree.abs_path, .root = &worktree.root, .fd = worktree.fd, .snapshot = &worktree.snapshot };
}

pub fn deinit(self: *Scanner) void {
    _ = self;
}

pub fn process_scan(self: *Scanner, path: []const u8) !void {
    _ = self;
    _ = path;
}

pub fn process_events(self: *Scanner) !void {
    _ = self;
}

pub fn initial_scan(self: *Scanner) !void {
    const stat = try std.fs.File.stat(self.fd);

    const kind: Kind = switch (stat.kind) {
        .file => .file,
        .directory => .dir,
        else => return error.InvalidKind,
    };

    {
        self.snapshot.mutex.lock();
        defer self.snapshot.mutex.unlock();

        self.snapshot.entries.insert(self.root, .{ .kind = kind, .path = self.root });
    }

    if (kind == .dir) {
        //NOTE:
        //add to the queueu a message that scan the root dir
    }
}
