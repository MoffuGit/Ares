const std = @import("std");

const Monitor = @import("monitor/mod.zig");
const MonitorThread = @import("monitor/Thread.zig");

const Scanner = @import("scanner/mod.zig");
const ScannerThread = @import("scanner/Thread.zig");

const Snapshot = @import("Snapshot.zig");

const BPlusTree = @import("../datastruct/b_plus_tree.zig").BPlusTree;
pub const Entries = BPlusTree([]const u8, Entry, (struct {
    pub fn comp(a: *Entry, b: *Entry) std.math.Order {
        return std.mem.order(u8, a.path, b.path);
    }
}.comp));

pub const Entry = struct {
    path: []const u8,
    kind: Kind,
};

pub const Kind = enum { file, dir };

const Allocator = std.mem.Allocator;

const log = std.log.scoped(.worktree);

pub const Worktree = struct {
    alloc: Allocator,

    snapshot: Snapshot,

    abs_path: []u8,
    root: []u8,
    fd: i32 = -1,

    monitor: Monitor,
    monitor_thread: MonitorThread,
    monitor_thr: std.Thread,

    scanner: Scanner,
    scanner_thread: ScannerThread,
    scanner_thr: std.Thread,

    pub fn init(self: *Worktree, abs_path: []const u8, alloc: Allocator) !Worktree {
        const _abs_path: []u8 = try alloc.dupe(u8, abs_path.*);
        errdefer alloc.free(_abs_path);

        const root = try alloc.dupe(u8, std.fs.path.basename(_abs_path));
        errdefer alloc.free(root);

        const fd = try std.posix.open(_abs_path, .{}, .{});
        errdefer std.posix.close(fd);

        var monitor_thread = try MonitorThread.init(alloc, &self.monitor);
        errdefer monitor_thread.deinit();

        var scanner_thread = try ScannerThread.init(alloc, &self.scanner);
        errdefer scanner_thread.deinit();

        var monitor = try Monitor.init(alloc, self);
        errdefer monitor.deinit();

        var scanner = try Scanner.init(alloc, self);
        errdefer scanner.deinit();

        var snapshot = try Snapshot.init(alloc);
        errdefer snapshot.deinit();

        self.* = .{ .alloc = alloc, .snapshot = snapshot, .root = root, .fd = fd, .monitor = monitor, .monitor_thread = monitor_thread, .monitor_thr = undefined, .scanner = scanner, .scanner_thread = scanner_thread, .scanner_thr = undefined };

        self.monitor_thr = try std.Thread.spawn(.{}, MonitorThread.Thread.threadMain, .{&self.monitor_thread});
        self.scanner_thr = try std.Thread.spawn(.{}, ScannerThread.Thread.threadMain, .{&self.scanner_thread});
    }

    pub fn deinit(self: *Worktree) void {
        {
            self.monitor_thread.stop.notify() catch |err| {
                log.err("error notifying monitor thread to stop, may stall err={}", .{err});
            };
            self.monitor_thr.join();
        }

        {
            self.scanner_thread.stop.notify() catch |err| {
                log.err("error notifying scanner thread to stop, may stall err={}", .{err});
            };
            self.scanner_thr.join();
        }

        self.monitor.deinit();
        self.scanner.deinit();

        self.snapshot.deinit();

        self.alloc.free(self.abs_path);
        self.alloc.free(self.root);
        std.posix.close(self.fd);

        log.info("Worktree closed", .{});
    }

    pub fn start_initial_scan(self: *Worktree) !void {
        _ = self.scanner_thread.mailbox.push(.{.initialScan}, .instant);
        self.scanner_thread.wakeup.notify() catch |err| {
            log.err("error notifying scanner thread to wakeup, err={}", .{err});
        };
    }
};
