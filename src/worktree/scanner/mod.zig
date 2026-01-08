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

pub fn process_scan(self: *Scanner, path: []const u8, abs_path: []const u8) !void {
    const dir = try std.fs.openDirAbsolute(abs_path, .{ .iterate = true });
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        const kind: Kind = switch (entry.kind) {
            .directory => .dir,
            .file => .file,
            else => continue,
        };
        const child_abs_path = std.fmt.allocPrint(self.alloc, "{}/{}", .{ abs_path, entry.name });
        const child_path = std.fmt.allocPrint(self.alloc, "{}/{}", .{ path, entry.name });

        {
            self.snapshot.mutex.lock();
            defer self.snapshot.mutex.unlock();

            self.snapshot.entries.insert(child_path, .{ .kind = kind, .path = child_path });
        }

        if (kind == .dir) {
            self.worktree.scanner_thread.mailbox.push(.{ .scan = .{ .abs_path = child_abs_path, .path = child_path } }, .instant);
        }
    }

    self.worktree.scanner_thread.wakeup.notify();
}

//NOTE:
//the events are going to send the absolute path
//you need to convert them into a valid key for the entries
//for that you will need to remove the prefix of the string
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
        self.worktree.scanner_thread.mailbox.push(.{ .scan = .{ .abs_path = self.abs_path, .path = self.root } }, .instant);
        self.worktree.scanner_thread.wakeup.notify();
    }
}
