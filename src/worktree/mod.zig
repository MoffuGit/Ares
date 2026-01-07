const std = @import("std");
const BPlusTree = @import("../datastruct/mod.zig").BPlusTree;
const Monitor = @import("monitor/mod.zig");
const MonitorThread = @import("monitor/Thread.zig");
const Scanner = @import("scanner/mod.zig");
const ScannerThread = @import("scanner/Thread.zig");
const Allocator = std.mem.Allocator;

const log = std.log.scoped(.worktree);

const Worktree = @This();

alloc: Allocator,

root: []u8 = undefined,
entries: BPlusTree(usize, usize) = undefined,

monitor: Monitor,
monitor_thread: MonitorThread,
monitor_thr: std.Thread,

scanner: Scanner,
scanner_thread: ScannerThread,
scanner_thr: std.Thread,

pub fn init(self: *Worktree, alloc: Allocator) !Worktree {
    var monitor_thread = try MonitorThread.init(alloc, &self);
    errdefer monitor_thread.deinit();

    var scanner_thread = try ScannerThread.init(alloc, &self);
    errdefer scanner_thread.deinit();

    var monitor = try Monitor.init(alloc);
    errdefer monitor.deinit();

    var scanner = try Scanner.init(alloc);
    errdefer scanner.deinit();

    self.* = .{ .alloc = alloc, .root = undefined, .entries = undefined, .monitor = monitor, .monitor_thread = monitor_thread, .monitor_thr = undefined, .scanner = scanner, .scanner_thread = scanner_thread, .scanner_thr = undefined };

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

    log.info("Worktree closed", .{});
}
