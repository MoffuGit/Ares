const std = @import("std");

const Monitor = @import("monitor/mod.zig");
const MonitorThread = @import("monitor/Thread.zig");

const Scanner = @import("scanner/mod.zig");
const ScannerThread = @import("scanner/Thread.zig");

const Snapshot = @import("Snapshot.zig");

const BPlusTree = @import("../datastruct/b_plus_tree.zig").BPlusTree;

fn entryOrder(a: []const u8, b: []const u8) std.math.Order {
    return std.mem.order(u8, a, b);
}

pub const Entries = BPlusTree([]const u8, Entry, entryOrder);

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

    // monitor: Monitor,
    // monitor_thread: MonitorThread,
    // monitor_thr: std.Thread,

    scanner: Scanner,
    scanner_thread: ScannerThread,
    scanner_thr: std.Thread,

    pub fn create(abs_path: []const u8, alloc: Allocator) !*Worktree {
        const worktree = try alloc.create(Worktree);
        try worktree.init(abs_path, alloc);

        return worktree;
    }

    pub fn destroy(self: *Worktree) void {
        self.deinit();
        self.alloc.destroy(self);
    }

    pub fn init(self: *Worktree, abs_path: []const u8, alloc: Allocator) !void {
        const _abs_path = try alloc.dupe(u8, abs_path);
        errdefer alloc.free(_abs_path);

        const root = try alloc.dupe(u8, std.fs.path.basename(_abs_path));
        errdefer alloc.free(root);

        // var monitor_thread = try MonitorThread.init(alloc, &self.monitor);
        // errdefer monitor_thread.deinit();

        var scanner_thread = try ScannerThread.init(alloc, &self.scanner);
        errdefer scanner_thread.deinit();

        // var monitor = try Monitor.init(alloc, self);
        // errdefer monitor.deinit();

        var scanner = try Scanner.init(alloc, self, &self.snapshot, _abs_path, root);
        errdefer scanner.deinit();

        var snapshot = try Snapshot.init(alloc);
        errdefer snapshot.deinit();

        self.* = .{ .alloc = alloc, .snapshot = snapshot, .root = root, .abs_path = _abs_path, .scanner = scanner, .scanner_thread = scanner_thread, .scanner_thr = undefined };
        // .monitor = monitor, .monitor_thread = monitor_thread, .monitor_thr = undefined

        // self.monitor_thr = try std.Thread.spawn(.{}, MonitorThread.Thread.threadMain, .{&self.monitor_thread});
        self.scanner_thr = try std.Thread.spawn(.{}, ScannerThread.Thread.threadMain, .{&self.scanner_thread});
    }

    pub fn deinit(self: *Worktree) void {
        // {
        //     self.monitor_thread.stop.notify() catch |err| {
        //         log.err("error notifying monitor thread to stop, may stall err={}", .{err});
        //     };
        //     self.monitor_thr.join();
        // }

        {
            self.scanner_thread.stop.notify() catch |err| {
                log.err("error notifying scanner thread to stop, may stall err={}", .{err});
            };
            self.scanner_thr.join();
        }

        self.scanner_thread.deinit();
        self.scanner.deinit();

        // self.monitor.deinit();

        self.snapshot.deinit();

        self.alloc.free(self.abs_path);
        self.alloc.free(self.root);

        log.info("Worktree closed", .{});
    }

    pub fn initial_scan(self: *Worktree) !void {
        _ = self.scanner_thread.mailbox.push(.initialScan, .instant);
        self.scanner_thread.wakeup.notify() catch |err| {
            log.err("error notifying scanner thread to wakeup, err={}", .{err});
        };
    }
};
