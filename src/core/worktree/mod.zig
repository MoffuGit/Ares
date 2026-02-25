// const std = @import("std");
// const Allocator = std.mem.Allocator;
//
// const BPlusTree = @import("datastruct").BPlusTree;
// const xev = @import("../global.zig").xev;
//
// const Stat = @import("../io/mod.zig").Stat;
//
// const Scanner = @import("scanner/mod.zig");
//
// const ScannerThread = @import("scanner/Thread.zig");
// const Snapshot = @import("Snapshot.zig");
//
// pub const Entries = BPlusTree([]const u8, Entry, entryOrder);
// fn entryOrder(a: []const u8, b: []const u8) std.math.Order {
//     return std.mem.order(u8, a, b);
// }
//
//
// const log = std.log.scoped(.worktree);
//
// pub const Worktree = struct {
//     alloc: Allocator,
//
//     snapshot: Snapshot,
//
//     abs_path: []u8,
//
//     scanner: Scanner,
//     scanner_thread: ScannerThread,
//     scanner_thr: std.Thread,
//
//     pub fn create(abs_path: []const u8, alloc: Allocator) !*Worktree {
//         const worktree = try alloc.create(Worktree);
//         try worktree.init(abs_path, alloc);
//
//         return worktree;
//     }
//
//     pub fn destroy(self: *Worktree) void {
//         self.deinit();
//         self.alloc.destroy(self);
//     }
//
//     pub fn init(self: *Worktree, abs_path: []const u8, alloc: Allocator) !void {
//         const _abs_path = try alloc.dupe(u8, abs_path);
//         errdefer alloc.free(_abs_path);
//
//         var snapshot = try Snapshot.init(alloc);
//         errdefer snapshot.deinit();
//
//         var scanner_thread = try ScannerThread.init(alloc, &self.scanner);
//         errdefer scanner_thread.deinit();
//
//         var scanner = try Scanner.init(alloc, self, &self.snapshot, _abs_path);
//         errdefer scanner.deinit();
//
//         self.* = .{
//             .alloc = alloc,
//             .snapshot = snapshot,
//             .abs_path = _abs_path,
//             .scanner = scanner,
//             .scanner_thread = scanner_thread,
//             .scanner_thr = undefined,
//         };
//
//         _ = self.scanner_thread.mailbox.push(.initialScan, .instant);
//         self.scanner_thread.wakeup.notify() catch |err| {
//             log.err("error notifying scanner thread to wakeup, err={}", .{err});
//         };
//     }
//
//     pub fn deinit(self: *Worktree) void {
//         {
//             self.scanner_thread.stop.notify() catch |err| {
//                 log.err("error notifying scanner thread to stop, may stall err={}", .{err});
//             };
//             self.scanner_thr.join();
//         }
//
//         self.scanner_thread.deinit();
//         self.scanner.deinit();
//
//         self.snapshot.deinit();
//
//         self.alloc.free(self.abs_path);
//
//         log.info("Worktree closed", .{});
//     }
// };
