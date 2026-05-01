// const std = @import("std");
// const xev = @import("../global.zig").xev;
// const Allocator = std.mem.Allocator;
// const Thread = @import("Thread.zig");
//
// const log = std.log.scoped(.monitor);
//
// pub const Monitor = @This();
//
// pub const WatchRequest = struct {
//     id: u64,
//     path: []u8,
//     alloc: Allocator,
//     userdata: ?*anyopaque,
//     callback: *const fn (userdata: ?*anyopaque, id: u64, events: u32) void,
// };
//
// pub const WatcherEntry = struct {
//     watcher: xev.FileSystem.Watcher,
//     path: []u8,
//     id: u64,
//     pending_events: u32 = 0,
//     dirty: bool = false,
//     monitor: *Monitor,
//     userdata: ?*anyopaque,
//     callback: *const fn (userdata: ?*anyopaque, id: u64, events: u32) void,
// };
//
// alloc: Allocator,
// watchers: std.AutoHashMap(u64, *WatcherEntry),
// pending_cancel: std.ArrayListUnmanaged(*WatcherEntry),
// dirty_queue: std.ArrayListUnmanaged(*WatcherEntry),
// next_id: u64 = 0,
// thread: Thread,
// thr: std.Thread,
//
// pub fn create(alloc: Allocator) !*Monitor {
//     const monitor = try alloc.create(Monitor);
//
//     monitor.* = .{
//         .alloc = alloc,
//         .watchers = std.AutoHashMap(u64, *WatcherEntry).init(alloc),
//         .pending_cancel = .{},
//         .dirty_queue = .{},
//         .thread = try Thread.init(alloc, monitor),
//         .thr = undefined,
//     };
//
//     monitor.thr = try std.Thread.spawn(.{}, Thread.threadMain, .{&monitor.thread});
//
//     return monitor;
// }
//
// pub fn destroy(self: *Monitor) void {
//     {
//         self.thread.stop.notify() catch |err| {
//             log.err("error notifying monitor thread to stop, may stall err={}", .{err});
//         };
//         self.thr.join();
//     }
//
//     self.thread.deinit();
//
//     var it = self.watchers.valueIterator();
//     while (it.next()) |entry_ptr| {
//         const entry = entry_ptr.*;
//         self.alloc.free(entry.path);
//         self.alloc.destroy(entry);
//     }
//     self.watchers.deinit();
//
//     for (self.pending_cancel.items) |entry| {
//         self.alloc.free(entry.path);
//         self.alloc.destroy(entry);
//     }
//     self.pending_cancel.deinit(self.alloc);
//     self.dirty_queue.deinit(self.alloc);
//
//     self.alloc.destroy(self);
//
//     log.info("Monitor closed", .{});
// }
//
// pub fn userdataValue(comptime Userdata: type, v: ?*anyopaque) ?*Userdata {
//     // Void userdata is always a null pointer.
//     if (Userdata == void) return null;
//     return @ptrCast(@alignCast(v));
// }
//
// pub fn watchPath(
//     self: *Monitor,
//     abs_path: []const u8,
//     comptime Userdata: type,
//     userdata: ?*Userdata,
//     comptime callback: *const fn (userdata: ?*Userdata, id: u64, events: u32) void,
// ) !u64 {
//     const id = self.next_id;
//     self.next_id += 1;
//
//     const path = try self.alloc.dupe(u8, abs_path);
//
//     const entry = self.alloc.create(WatcherEntry) catch {
//         log.err("failed to allocate watcher entry", .{});
//         self.alloc.free(path);
//         return error.OutOfMemory;
//     };
//
//     entry.* = .{
//         .watcher = .{},
//         .path = path,
//         .id = id,
//         .monitor = self,
//         .userdata = userdata,
//         .callback = (struct {
//             fn cb(inner_userdata: ?*anyopaque, inner_id: u64, inner_events: u32) void {
//                 return @call(.always_inline, callback, .{ userdataValue(Userdata, inner_userdata), inner_id, inner_events });
//             }
//         }.cb),
//     };
//
//     self.thread.fs.watch(path, &entry.watcher, WatcherEntry, entry, fsEventsCallback) catch {
//         // log.err("failed to start watcher for '{s}': {}", .{ path, err });
//         self.alloc.free(path);
//         self.alloc.destroy(entry);
//         return error.OutOfMemory;
//     };
//
//     self.watchers.put(id, entry) catch {
//         log.err("failed to track watcher id={}", .{id});
//         self.thread.fs.cancel(&entry.watcher);
//         self.alloc.free(entry.path);
//         self.alloc.destroy(entry);
//         return error.OutOfMemory;
//     };
//
//     return id;
// }
//
// fn fsEventsCallback(
//     entry: ?*Monitor.WatcherEntry,
//     _: *xev.FileSystem.Watcher,
//     _: []const u8,
//     events: u32,
// ) xev.CallbackAction {
//     const e = entry orelse return .rearm;
//     e.pending_events |= events;
//     if (!e.dirty) {
//         e.dirty = true;
//         e.monitor.dirty_queue.append(e.monitor.alloc, e) catch {};
//     }
//     return .rearm;
// }
//
// pub fn unwatchPath(self: *Monitor, id: u64) void {
//     self.removeWatcher(&self.thread.fs, id);
// }
//
// pub fn addWatcher(
//     self: *Monitor,
//     fs: *xev.FileSystem,
//     req: *WatchRequest,
//     comptime callback: *const fn (?*WatcherEntry, *xev.FileSystem.Watcher, []const u8, u32) xev.CallbackAction,
// ) void {
//     const id = req.id;
//
//     const entry = self.alloc.create(WatcherEntry) catch {
//         log.err("failed to allocate watcher entry", .{});
//         self.alloc.free(req.path);
//         self.alloc.destroy(req);
//         return;
//     };
//
//     entry.* = .{
//         .watcher = .{},
//         .path = req.path,
//         .id = id,
//         .monitor = self,
//         .userdata = req.userdata,
//         .callback = req.callback,
//     };
//
//     fs.watch(req.path, &entry.watcher, WatcherEntry, entry, callback) catch {
//         // log.err("failed to start watcher for '{s}': {}", .{ req.path, err });
//         self.alloc.free(req.path);
//         self.alloc.destroy(entry);
//         self.alloc.destroy(req);
//         return;
//     };
//
//     self.watchers.put(id, entry) catch {
//         log.err("failed to track watcher id={}", .{id});
//         fs.cancel(&entry.watcher);
//         self.alloc.free(entry.path);
//         self.alloc.destroy(entry);
//         self.alloc.destroy(req);
//         return;
//     };
//
//     self.alloc.destroy(req);
// }
//
// pub fn removeWatcher(self: *Monitor, fs: *xev.FileSystem, id: u64) void {
//     if (self.watchers.fetchRemove(id)) |kv| {
//         const entry = kv.value;
//         entry.pending_events = 0;
//         entry.dirty = false;
//         fs.cancel(&entry.watcher);
//         self.pending_cancel.append(self.alloc, entry) catch |err| {
//             log.err("failed to add watcher to pending_cancel queue: {}", .{err});
//             self.alloc.free(entry.path);
//             self.alloc.destroy(entry);
//         };
//         log.debug("monitor removing watcher: id={}", .{id});
//     } else {
//         log.warn("no watcher found for id={}", .{id});
//     }
// }
//
// pub fn cleanupCancelledWatchers(self: *Monitor) void {
//     var i: usize = 0;
//     while (i < self.pending_cancel.items.len) {
//         const entry = self.pending_cancel.items[i];
//         if (entry.watcher.state() == .dead) {
//             log.debug("cleaning up dead watcher for id={}", .{entry.id});
//             self.alloc.free(entry.path);
//             self.alloc.destroy(entry);
//             _ = self.pending_cancel.swapRemove(i);
//         } else {
//             i += 1;
//         }
//     }
// }
//
// pub fn flushPendingEvents(self: *Monitor) void {
//     for (self.dirty_queue.items) |entry| {
//         const events = entry.pending_events;
//         entry.pending_events = 0;
//         entry.dirty = false;
//         if (events != 0) {
//             entry.callback(entry.userdata, entry.id, events);
//         }
//     }
//     self.dirty_queue.clearRetainingCapacity();
// }
