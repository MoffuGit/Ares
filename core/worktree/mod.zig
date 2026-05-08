const std = @import("std");
const Allocator = std.mem.Allocator;

const global = @import("../global.zig");
const Monitor = @import("../monitor/mod.zig");
const Scanner = @import("scanner/mod.zig");
const ScannerThread = @import("scanner/Thread.zig");
const Io = @import("../io/mod.zig");
pub const Entry = Snapshot.Entry;

const Snapshot = @import("Snapshot.zig");

const log = std.log.scoped(.worktree);

pub const Worktree = struct {
    alloc: Allocator,

    snapshot: Snapshot,

    abs_path: []u8,

    scanner: Scanner,
    scanner_thread: ScannerThread,
    scanner_thr: std.Thread,

    io: *Io,

    pub fn create(abs_path: []const u8, io: *Io, monitor: *Monitor, alloc: Allocator) !*Worktree {
        const worktree = try alloc.create(Worktree);
        try worktree.init(io, monitor, abs_path, alloc);

        return worktree;
    }

    pub fn destroy(self: *Worktree) void {
        self.deinit();
        self.alloc.destroy(self);
    }

    pub fn init(self: *Worktree, io: *Io, monitor: *Monitor, abs_path: []const u8, alloc: Allocator) !void {
        const _abs_path = try alloc.dupe(u8, abs_path);
        errdefer alloc.free(_abs_path);

        var snapshot = try Snapshot.init(alloc);
        errdefer snapshot.deinit();

        var scanner_thread = try ScannerThread.init(alloc, &self.scanner);
        errdefer scanner_thread.deinit();

        var scanner = try Scanner.init(alloc, &global.state.thread_pool, monitor, &self.snapshot, _abs_path);
        errdefer scanner.deinit();

        self.* = .{
            .alloc = alloc,
            .snapshot = snapshot,
            .abs_path = _abs_path,
            .scanner = scanner,
            .scanner_thread = scanner_thread,
            .scanner_thr = undefined,
            .io = io,
        };

        self.scanner_thr = try std.Thread.spawn(.{}, ScannerThread.threadMain, .{&self.scanner_thread});

        _ = self.scanner_thread.mailbox.push(.initialScan, .instant);
        self.scanner_thread.wakeup.notify() catch |err| {
            log.err("error notifying scanner thread to wakeup, err={}", .{err});
        };
    }

    pub fn count(self: *Worktree) usize {
        self.snapshot.rwlock.lockShared();
        defer self.snapshot.rwlock.unlockShared();

        return self.snapshot.count();
    }

    pub fn getAbsPath(self: *Worktree, id: u64) ?[]const u8 {
        self.snapshot.rwlock.lockShared();
        defer self.snapshot.rwlock.unlockShared();

        return self.snapshot.getAbsPathById(id);
    }

    pub fn loadFile(self: *Worktree, id: u64) ![]const u8 {
        const abs_path = self.getAbsPath(id) orelse return error.EntryNotFound;

        try self.io.readFile(abs_path);

        return abs_path;
    }

    pub fn deinit(self: *Worktree) void {
        {
            self.scanner.requestStop();
            self.scanner_thread.stop.notify() catch |err| {
                log.err("error notifying scanner thread to stop, may stall err={}", .{err});
            };
            self.scanner_thr.join();
        }

        self.scanner_thread.deinit();
        self.scanner.deinit();

        self.snapshot.deinit();

        self.alloc.free(self.abs_path);

        log.info("Worktree closed", .{});
    }
};

test {
    _ = Scanner;
}
