const std = @import("std");
const Allocator = std.mem.Allocator;
const worktreepkg = @import("../mod.zig");
const Worktree = worktreepkg.Worktree;
const Entry = worktreepkg.Entry;
const Kind = worktreepkg.Kind;
const Snapshot = @import("../Snapshot.zig");
const MonitorMessage = @import("../monitor/Message.zig").Message;

pub const Scanner = @This();

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

//NOTE:
//the events are going to send the absolute path
//you need to convert them into a valid key for the entries
//for that you will need to remove the prefix of the string
pub fn process_events(self: *Scanner) !void {
    _ = self;
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
