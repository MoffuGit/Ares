// const std = @import("std");
// const builtin = @import("builtin");
// const posix = std.posix;
// const double = @import("../../queue_double.zig");
// const tree = @import("../../tree.zig");
// const fspkg = @import("../fs.zig");
// const common = @import("../common.zig");
// const log = std.log.scoped(.fs_fsevents);
// const Fnv1a_32 = std.hash.Fnv1a_32;
//
// // --- CoreFoundation / CoreServices C bindings ---
//
// const CFAllocatorRef = ?*anyopaque;
// const CFTypeRef = *anyopaque;
// const CFStringRef = *anyopaque;
// const CFArrayRef = *anyopaque;
// const CFRunLoopRef = *anyopaque;
// const CFRunLoopSourceRef = *anyopaque;
// const CFIndex = isize;
// const CFAbsoluteTime = f64;
//
// const FSEventStreamRef = *anyopaque;
// const FSEventStreamEventId = u64;
// const FSEventStreamCreateFlags = u32;
// const FSEventStreamEventFlags = u32;
//
// const kFSEventStreamEventIdSinceNow: FSEventStreamEventId = 0xFFFFFFFFFFFFFFFF;
//
// const kFSEventStreamCreateFlagNoDefer: FSEventStreamCreateFlags = 0x00000002;
// const kFSEventStreamCreateFlagFileEvents: FSEventStreamCreateFlags = 0x00000010;
//
// const kFSEventStreamEventFlagMustScanSubDirs: FSEventStreamEventFlags = 0x00000001;
// const kFSEventStreamEventFlagUserDropped: FSEventStreamEventFlags = 0x00000002;
// const kFSEventStreamEventFlagKernelDropped: FSEventStreamEventFlags = 0x00000004;
// const kFSEventStreamEventFlagEventIdsWrapped: FSEventStreamEventFlags = 0x00000008;
// const kFSEventStreamEventFlagHistoryDone: FSEventStreamEventFlags = 0x00000010;
// const kFSEventStreamEventFlagRootChanged: FSEventStreamEventFlags = 0x00000020;
// const kFSEventStreamEventFlagMount: FSEventStreamEventFlags = 0x00000040;
// const kFSEventStreamEventFlagUnmount: FSEventStreamEventFlags = 0x00000080;
//
// const kFSEventStreamEventFlagItemCreated: FSEventStreamEventFlags = 0x00000100;
// const kFSEventStreamEventFlagItemRemoved: FSEventStreamEventFlags = 0x00000200;
// const kFSEventStreamEventFlagItemInodeMetaMod: FSEventStreamEventFlags = 0x00000400;
// const kFSEventStreamEventFlagItemRenamed: FSEventStreamEventFlags = 0x00000800;
// const kFSEventStreamEventFlagItemModified: FSEventStreamEventFlags = 0x00001000;
// const kFSEventStreamEventFlagItemFinderInfoMod: FSEventStreamEventFlags = 0x00002000;
// const kFSEventStreamEventFlagItemChangeOwner: FSEventStreamEventFlags = 0x00004000;
// const kFSEventStreamEventFlagItemXattrMod: FSEventStreamEventFlags = 0x00008000;
// const kFSEventStreamEventFlagItemIsFile: FSEventStreamEventFlags = 0x00010000;
// const kFSEventStreamEventFlagItemIsDir: FSEventStreamEventFlags = 0x00020000;
// const kFSEventStreamEventFlagItemIsSymlink: FSEventStreamEventFlags = 0x00040000;
//
// const kFSEventsModified =
//     kFSEventStreamEventFlagItemChangeOwner |
//     kFSEventStreamEventFlagItemFinderInfoMod |
//     kFSEventStreamEventFlagItemInodeMetaMod |
//     kFSEventStreamEventFlagItemModified |
//     kFSEventStreamEventFlagItemXattrMod;
//
// const kFSEventsRenamed =
//     kFSEventStreamEventFlagItemCreated |
//     kFSEventStreamEventFlagItemRemoved |
//     kFSEventStreamEventFlagItemRenamed;
//
// const kFSEventsSystem =
//     kFSEventStreamEventFlagUserDropped |
//     kFSEventStreamEventFlagKernelDropped |
//     kFSEventStreamEventFlagEventIdsWrapped |
//     kFSEventStreamEventFlagHistoryDone |
//     kFSEventStreamEventFlagMount |
//     kFSEventStreamEventFlagUnmount |
//     kFSEventStreamEventFlagRootChanged;
//
// const FSEventStreamCallback = *const fn (
//     stream_ref: FSEventStreamRef,
//     client_info: ?*anyopaque,
//     num_events: usize,
//     event_paths: [*][*:0]const u8,
//     event_flags: [*]const FSEventStreamEventFlags,
//     event_ids: [*]const FSEventStreamEventId,
// ) callconv(.c) void;
//
// const FSEventStreamContext = extern struct {
//     version: CFIndex = 0,
//     info: ?*anyopaque = null,
//     retain: ?*anyopaque = null,
//     release: ?*anyopaque = null,
//     copy_description: ?*anyopaque = null,
// };
//
// const CFRunLoopSourceContext = extern struct {
//     version: CFIndex = 0,
//     info: ?*anyopaque = null,
//     retain: ?*anyopaque = null,
//     release: ?*anyopaque = null,
//     copy_description: ?*anyopaque = null,
//     equal: ?*anyopaque = null,
//     hash: ?*anyopaque = null,
//     schedule: ?*anyopaque = null,
//     cancel: ?*anyopaque = null,
//     perform: ?*const fn (?*anyopaque) callconv(.c) void = null,
// };
//
// extern "c" fn CFArrayCreate(
//     allocator: CFAllocatorRef,
//     values: [*]const ?*anyopaque,
//     num_values: CFIndex,
//     callbacks: ?*const anyopaque,
// ) CFArrayRef;
//
// extern "c" fn CFRelease(cf: CFTypeRef) void;
//
// extern "c" fn CFRunLoopGetCurrent() CFRunLoopRef;
// extern "c" fn CFRunLoopRun() void;
// extern "c" fn CFRunLoopStop(rl: CFRunLoopRef) void;
// extern "c" fn CFRunLoopWakeUp(rl: CFRunLoopRef) void;
// extern "c" fn CFRunLoopAddSource(rl: CFRunLoopRef, source: CFRunLoopSourceRef, mode: CFStringRef) void;
// extern "c" fn CFRunLoopRemoveSource(rl: CFRunLoopRef, source: CFRunLoopSourceRef, mode: CFStringRef) void;
// extern "c" fn CFRunLoopSourceCreate(allocator: CFAllocatorRef, order: CFIndex, context: *CFRunLoopSourceContext) CFRunLoopSourceRef;
// extern "c" fn CFRunLoopSourceSignal(source: CFRunLoopSourceRef) void;
//
// extern "c" fn CFStringCreateWithFileSystemRepresentation(allocator: CFAllocatorRef, buffer: [*:0]const u8) ?CFStringRef;
//
// extern "c" var kCFRunLoopDefaultMode: CFStringRef;
//
// extern "c" fn FSEventStreamCreate(
//     allocator: CFAllocatorRef,
//     callback: FSEventStreamCallback,
//     context: *FSEventStreamContext,
//     paths_to_watch: CFArrayRef,
//     since_when: FSEventStreamEventId,
//     latency: CFAbsoluteTime,
//     flags: FSEventStreamCreateFlags,
// ) ?FSEventStreamRef;
//
// extern "c" fn FSEventStreamScheduleWithRunLoop(
//     stream_ref: FSEventStreamRef,
//     run_loop: CFRunLoopRef,
//     run_loop_mode: CFStringRef,
// ) void;
//
// extern "c" fn FSEventStreamStart(stream_ref: FSEventStreamRef) bool;
// extern "c" fn FSEventStreamStop(stream_ref: FSEventStreamRef) void;
// extern "c" fn FSEventStreamInvalidate(stream_ref: FSEventStreamRef) void;
// extern "c" fn FSEventStreamRelease(stream_ref: FSEventStreamRef) void;
//
// // --- FSEvents file system watcher implementation ---
//
// pub fn FileSystem(comptime xev: type) type {
//     return struct {
//         const Self = @This();
//
//         const Callback = fspkg.Callback(xev, @This());
//         const NoopCallback = fspkg.NoopCallback(xev, @This());
//
//         const CancelationCallback = fspkg.CancelationCallback(@This());
//         const NoopCancelation = fspkg.NoopCancelation(@This());
//
//         const State = enum(u1) {
//             dead = 0,
//             active = 1,
//         };
//
//         pub const Watcher = struct {
//             fs: ?*Self = null,
//
//             rb_node: tree.IntrusiveField(Watcher) = .{},
//
//             next: ?*Watcher = null,
//             prev: ?*Watcher = null,
//
//             userdata: ?*anyopaque = null,
//             callback: Callback = NoopCallback,
//
//             wd: u32 = 0,
//             path: []const u8 = undefined,
//             realpath_buf: [std.fs.max_path_bytes]u8 = undefined,
//             realpath: []const u8 = &.{},
//
//             watchers: double.Intrusive(Watcher) = .{},
//
//             flags: packed struct {
//                 state: State = .dead,
//             } = .{},
//
//             pub fn state(self: Watcher) State {
//                 return self.flags.state;
//             }
//
//             pub fn invoke(self: *Watcher, path: []const u8, res: u32) xev.CallbackAction {
//                 return self.callback(self.userdata, self, path, res);
//             }
//
//             pub fn compare(a: *Watcher, b: *Watcher) std.math.Order {
//                 if (a.wd > b.wd) return .gt;
//                 if (a.wd < b.wd) return .lt;
//                 return .eq;
//             }
//         };
//
//         const PendingEvent = struct {
//             next: ?*PendingEvent = null,
//             event_flags: u32,
//             path_len: u16,
//             path_buf: [std.fs.max_path_bytes]u8,
//         };
//
//         tree: tree.Intrusive(Watcher, Watcher.compare) = .{},
//         loop: *xev.Loop = undefined,
//         active: usize = 0,
//
//         // Async wakeup for cross-thread notification
//         async_wakeup: xev.Async = undefined,
//         async_c: xev.Completion = .{},
//
//         // CFRunLoop thread state
//         cf_thread: ?std.Thread = null,
//         cf_runloop: ?CFRunLoopRef = null,
//         cf_signal_source: ?CFRunLoopSourceRef = null,
//
//         // Synchronization
//         mutex: std.Thread.Mutex = .{},
//         cf_ready: std.Thread.ResetEvent = .{},
//
//         // Stream state (protected by mutex)
//         fsevent_stream: ?FSEventStreamRef = null,
//         need_reschedule: bool = false,
//         shutting_down: bool = false,
//
//         // Event queue: events from CF thread to main loop (protected by mutex)
//         event_head: ?*PendingEvent = null,
//         event_tail: ?*PendingEvent = null,
//
//         pub fn init() Self {
//             return .{};
//         }
//
//         pub fn deinit(self: *Self) void {
//             // Signal shutdown
//             self.mutex.lock();
//             self.shutting_down = true;
//             self.mutex.unlock();
//
//             // Stop the CFRunLoop thread
//             if (self.cf_runloop) |rl| {
//                 if (self.cf_signal_source) |src| {
//                     CFRunLoopSourceSignal(src);
//                     CFRunLoopWakeUp(rl);
//                 }
//             }
//
//             if (self.cf_thread) |t| {
//                 t.join();
//                 self.cf_thread = null;
//             }
//
//             // Clean up signal source
//             if (self.cf_signal_source) |src| {
//                 CFRelease(src);
//                 self.cf_signal_source = null;
//             }
//
//             // Drain remaining events
//             self.mutex.lock();
//             while (self.event_head) |ev| {
//                 self.event_head = ev.next;
//                 std.heap.c_allocator.destroy(ev);
//             }
//             self.event_tail = null;
//             self.mutex.unlock();
//
//             // Clean up async
//             self.async_wakeup.deinit();
//         }
//
//         pub fn start(self: *Self, loop: *xev.Loop) !void {
//             self.loop = loop;
//
//             // Initialize async wakeup
//             self.async_wakeup = try xev.Async.init();
//
//             // Register async wait on the loop
//             self.async_wakeup.wait(loop, &self.async_c, Self, self, asyncCallback);
//
//             // Start the CFRunLoop thread
//             self.cf_thread = try std.Thread.spawn(.{}, cfRunLoopThread, .{self});
//
//             // Wait for the CF thread to be ready
//             self.cf_ready.wait();
//         }
//
//         pub fn watch(self: *Self, path: []const u8, watcher: *Watcher, comptime Userdata: type, userdata: ?*Userdata, comptime cb: *const fn (
//             ud: ?*Userdata,
//             watcher: *Watcher,
//             path: []const u8,
//             result: u32,
//         ) xev.CallbackAction) !void {
//             if (watcher.state() != .dead) {
//                 return;
//             }
//
//             const wd = Fnv1a_32.hash(path);
//
//             // Resolve realpath
//             var realpath_buf: [std.fs.max_path_bytes]u8 = undefined;
//             const realpath = std.fs.cwd().realpath(path, &realpath_buf) catch path;
//
//             watcher.* = .{
//                 .callback = (struct {
//                     fn callback(
//                         ud: ?*anyopaque,
//                         _watcher: *Watcher,
//                         _path: []const u8,
//                         result: u32,
//                     ) xev.CallbackAction {
//                         return @call(.always_inline, cb, .{ common.userdataValue(Userdata, ud), _watcher, _path, result });
//                     }
//                 }).callback,
//                 .userdata = userdata,
//                 .wd = wd,
//                 .path = path,
//                 .fs = self,
//             };
//
//             // Store realpath in the watcher's own buffer
//             @memcpy(watcher.realpath_buf[0..realpath.len], realpath);
//             watcher.realpath = watcher.realpath_buf[0..realpath.len];
//
//             if (self.tree.find(watcher)) |w| {
//                 w.watchers.push(watcher);
//             } else {
//                 self.tree.insert(watcher);
//             }
//
//             watcher.flags.state = .active;
//             self.active += 1;
//
//             // Signal the CF thread to reschedule the stream
//             self.signalReschedule();
//         }
//
//         pub fn cancel(self: *Self, w: *Watcher) void {
//             if (self.tree.find(w)) |watcher| {
//                 self.active -= 1;
//                 w.flags.state = .dead;
//
//                 if (watcher != w) {
//                     watcher.watchers.remove(w);
//                     return;
//                 }
//
//                 if (watcher.watchers.pop()) |replace| {
//                     self.tree.replace(watcher, replace) catch {};
//                 } else {
//                     _ = self.tree.remove(w);
//                 }
//
//                 self.signalReschedule();
//             }
//         }
//
//         pub fn cancelWithCallback(self: *Self, w: *Watcher, comptime Userdata: type, userdata: ?*Userdata, comptime cb: *const fn (ud: ?*Userdata, w: *Watcher) void) void {
//             if (self.tree.find(w)) |watcher| {
//                 self.active -= 1;
//                 w.flags.state = .dead;
//
//                 if (watcher != w) {
//                     watcher.watchers.remove(w);
//                     @call(.always_inline, cb, .{ userdata, w });
//                     return;
//                 }
//
//                 if (watcher.watchers.pop()) |replace| {
//                     self.tree.replace(watcher, replace) catch {};
//                 } else {
//                     _ = self.tree.remove(w);
//                 }
//
//                 @call(.always_inline, cb, .{ userdata, watcher });
//
//                 self.signalReschedule();
//             }
//         }
//
//         fn signalReschedule(self: *Self) void {
//             self.mutex.lock();
//             self.need_reschedule = true;
//             self.mutex.unlock();
//
//             if (self.cf_runloop) |rl| {
//                 if (self.cf_signal_source) |src| {
//                     CFRunLoopSourceSignal(src);
//                     CFRunLoopWakeUp(rl);
//                 }
//             }
//         }
//
//         // --- CF RunLoop thread ---
//
//         fn cfRunLoopThread(self: *Self) void {
//             const rl = CFRunLoopGetCurrent();
//
//             // Create a custom source for signaling from the main thread
//             var ctx = CFRunLoopSourceContext{
//                 .info = self,
//                 .perform = cfSourceCallback,
//             };
//             const source = CFRunLoopSourceCreate(null, 0, &ctx);
//             CFRunLoopAddSource(rl, source, kCFRunLoopDefaultMode);
//
//             self.mutex.lock();
//             self.cf_runloop = rl;
//             self.cf_signal_source = source;
//             self.mutex.unlock();
//
//             // Signal that we're ready
//             self.cf_ready.set();
//
//             // Do initial schedule if there are already paths
//             self.rescheduleStream();
//
//             // Run the CFRunLoop
//             CFRunLoopRun();
//
//             // Cleanup: destroy any active stream
//             self.destroyStream();
//
//             // Remove source from runloop
//             CFRunLoopRemoveSource(rl, source, kCFRunLoopDefaultMode);
//         }
//
//         fn cfSourceCallback(info: ?*anyopaque) callconv(.c) void {
//             const self: *Self = @ptrCast(@alignCast(info.?));
//
//             self.mutex.lock();
//             const shutting_down = self.shutting_down;
//             const need_reschedule = self.need_reschedule;
//             self.need_reschedule = false;
//             self.mutex.unlock();
//
//             if (shutting_down) {
//                 if (self.cf_runloop) |rl| {
//                     CFRunLoopStop(rl);
//                 }
//                 return;
//             }
//
//             if (need_reschedule) {
//                 self.rescheduleStream();
//             }
//         }
//
//         fn destroyStream(self: *Self) void {
//             self.mutex.lock();
//             const stream = self.fsevent_stream;
//             self.fsevent_stream = null;
//             self.mutex.unlock();
//
//             if (stream) |s| {
//                 FSEventStreamStop(s);
//                 FSEventStreamInvalidate(s);
//                 FSEventStreamRelease(s);
//             }
//         }
//
//         fn rescheduleStream(self: *Self) void {
//             // Destroy existing stream
//             self.destroyStream();
//
//             // Collect all watched paths from the tree
//             const allocator = std.heap.c_allocator;
//
//             // Count watchers
//             var count: usize = 0;
//             {
//                 var it = self.tree.iter();
//                 while (it.next()) |_| {
//                     count += 1;
//                 }
//             }
//
//             if (count == 0) return;
//
//             // Build CFArray of paths
//             const cf_strings = allocator.alloc(?*anyopaque, count) catch return;
//             defer allocator.free(cf_strings);
//
//             var i: usize = 0;
//             {
//                 var it = self.tree.iter();
//                 while (it.next()) |w| {
//                     // Create a null-terminated copy for CFString
//                     var path_buf: [std.fs.max_path_bytes + 1]u8 = undefined;
//                     if (w.realpath.len >= path_buf.len) continue;
//                     @memcpy(path_buf[0..w.realpath.len], w.realpath);
//                     path_buf[w.realpath.len] = 0;
//
//                     const cf_str = CFStringCreateWithFileSystemRepresentation(
//                         null,
//                         path_buf[0..w.realpath.len :0],
//                     ) orelse continue;
//
//                     cf_strings[i] = cf_str;
//                     i += 1;
//                 }
//             }
//
//             if (i == 0) return;
//
//             const cf_paths = CFArrayCreate(null, cf_strings.ptr, @intCast(i), null);
//
//             // Release the CFStrings (CFArray with NULL callbacks doesn't retain them)
//             for (cf_strings[0..i]) |s| {
//                 if (s) |str| CFRelease(str);
//             }
//
//             // Create the stream
//             var ctx = FSEventStreamContext{
//                 .info = self,
//             };
//
//             const latency: CFAbsoluteTime = 0.05;
//             const flags: FSEventStreamCreateFlags = kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagFileEvents;
//
//             const stream = FSEventStreamCreate(
//                 null,
//                 fseventsCallback,
//                 &ctx,
//                 cf_paths,
//                 kFSEventStreamEventIdSinceNow,
//                 latency,
//                 flags,
//             ) orelse {
//                 CFRelease(cf_paths);
//                 return;
//             };
//
//             // Schedule and start
//             const rl = self.cf_runloop orelse {
//                 FSEventStreamRelease(stream);
//                 CFRelease(cf_paths);
//                 return;
//             };
//
//             FSEventStreamScheduleWithRunLoop(stream, rl, kCFRunLoopDefaultMode);
//
//             if (!FSEventStreamStart(stream)) {
//                 FSEventStreamInvalidate(stream);
//                 FSEventStreamRelease(stream);
//                 CFRelease(cf_paths);
//                 return;
//             }
//
//             self.mutex.lock();
//             self.fsevent_stream = stream;
//             self.mutex.unlock();
//
//             CFRelease(cf_paths);
//         }
//
//         fn fseventsCallback(
//             _: FSEventStreamRef,
//             client_info: ?*anyopaque,
//             num_events: usize,
//             event_paths: [*][*:0]const u8,
//             event_flags: [*]const FSEventStreamEventFlags,
//             _: [*]const FSEventStreamEventId,
//         ) callconv(.c) void {
//             const self: *Self = @ptrCast(@alignCast(client_info.?));
//
//             const allocator = std.heap.c_allocator;
//             var enqueued: bool = false;
//
//             for (0..num_events) |idx| {
//                 const flags = event_flags[idx];
//
//                 // Skip system events
//                 if (flags & kFSEventsSystem != 0) continue;
//
//                 const raw_path = std.mem.span(event_paths[idx]);
//                 if (raw_path.len > std.fs.max_path_bytes) continue;
//
//                 // Determine event type
//                 var ev_type: u32 = 0;
//                 if (flags & kFSEventsRenamed != 0) {
//                     ev_type = 1; // rename
//                 } else if (flags & kFSEventsModified != 0) {
//                     ev_type = 2; // change
//                 } else {
//                     ev_type = 2; // default to change for file events
//                 }
//
//                 // Allocate and enqueue
//                 const event = allocator.create(PendingEvent) catch continue;
//                 event.* = .{
//                     .next = null,
//                     .event_flags = ev_type,
//                     .path_len = @intCast(raw_path.len),
//                     .path_buf = undefined,
//                 };
//                 @memcpy(event.path_buf[0..raw_path.len], raw_path);
//
//                 self.mutex.lock();
//                 if (self.event_tail) |tail| {
//                     tail.next = event;
//                 } else {
//                     self.event_head = event;
//                 }
//                 self.event_tail = event;
//                 self.mutex.unlock();
//
//                 enqueued = true;
//             }
//
//             // Wake the main loop via async
//             if (enqueued) {
//                 self.async_wakeup.notify() catch {};
//             }
//         }
//
//         // --- Main loop async callback ---
//
//         fn asyncCallback(
//             self_: ?*Self,
//             _: *xev.Loop,
//             _: *xev.Completion,
//             _: xev.Async.WaitError!void,
//         ) xev.CallbackAction {
//             const self = self_.?;
//
//             // Process queued events
//             self.mutex.lock();
//             var head = self.event_head;
//             self.event_head = null;
//             self.event_tail = null;
//             self.mutex.unlock();
//
//             const allocator = std.heap.c_allocator;
//
//             while (head) |event| {
//                 const next = event.next;
//                 defer {
//                     allocator.destroy(event);
//                     head = next;
//                 }
//
//                 const event_path = event.path_buf[0..event.path_len];
//                 const ev_flags = event.event_flags;
//
//                 // Find matching watchers in the tree
//                 var it = self.tree.iter();
//                 while (it.next()) |watcher| {
//                     // Check if this event path matches or is under this watcher's path
//                     if (!pathMatches(event_path, watcher.realpath)) continue;
//
//                     // Compute the path to pass to the callback
//                     const cb_path = if (event_path.len > watcher.realpath.len and event_path[watcher.realpath.len] == '/')
//                         event_path
//                     else
//                         watcher.path;
//
//                     const action = watcher.invoke(cb_path, ev_flags);
//
//                     // Invoke secondary watchers
//                     var watchers_list = watcher.watchers;
//                     watcher.watchers = .{};
//
//                     while (watchers_list.pop()) |w| {
//                         switch (w.invoke(cb_path, ev_flags)) {
//                             .disarm => {
//                                 w.flags.state = .dead;
//                                 self.active -= 1;
//                             },
//                             .rearm => {
//                                 watcher.watchers.push(w);
//                             },
//                         }
//                     }
//
//                     if (action == .disarm) {
//                         watcher.flags.state = .dead;
//                         self.active -= 1;
//
//                         if (watcher.watchers.pop()) |replace| {
//                             self.tree.replace(watcher, replace) catch {};
//                         } else {
//                             _ = self.tree.remove(watcher);
//                         }
//                     }
//                 }
//             }
//
//             return .rearm;
//         }
//
//         fn pathMatches(event_path: []const u8, watch_path: []const u8) bool {
//             if (event_path.len < watch_path.len) return false;
//             if (!std.mem.eql(u8, event_path[0..watch_path.len], watch_path)) return false;
//             if (event_path.len == watch_path.len) return true;
//             return event_path[watch_path.len] == '/';
//         }
//
//         test {
//             _ = FileSystemTest(xev);
//         }
//     };
// }
//
// pub fn FileSystemTest(comptime xev: type) type {
//     return struct {
//         const testing = std.testing;
//         const FS = FileSystem(xev);
//
//         test "test fsevents file watcher" {
//             var loop = try xev.Loop.init(.{});
//             defer loop.deinit();
//
//             var fs = FS.init();
//             defer fs.deinit();
//             try fs.start(&loop);
//
//             _ = try loop.run(.no_wait);
//
//             const path1 = "test_path_fsevents_1";
//             const file = try std.fs.cwd().createFile(path1, .{});
//             defer std.fs.cwd().deleteFile(path1) catch {};
//
//             var counter: usize = 0;
//             const custom_callback = struct {
//                 fn invoke(ud: ?*usize, _: *FS.Watcher, _: []const u8, _: u32) xev.CallbackAction {
//                     ud.?.* += 1;
//                     return .rearm;
//                 }
//             }.invoke;
//
//             var watcher: FS.Watcher = .{};
//
//             try fs.watch(path1, &watcher, usize, &counter, custom_callback);
//
//             _ = try file.write("hello");
//             try file.sync();
//
//             // FSEvents has latency, need to wait a bit
//             std.Thread.sleep(100 * std.time.ns_per_ms);
//
//             _ = try loop.run(.no_wait);
//
//             // FSEvents coalesces events, so counter should be >= 1
//             try testing.expect(counter >= 1);
//         }
//
//         test "test fsevents cancel watcher" {
//             var loop = try xev.Loop.init(.{});
//             defer loop.deinit();
//
//             var fs = FS.init();
//             defer fs.deinit();
//             try fs.start(&loop);
//
//             const path = "test_path_fsevents_cancel";
//             _ = try std.fs.cwd().createFile(path, .{});
//             defer std.fs.cwd().deleteFile(path) catch {};
//
//             var counter: usize = 0;
//             const callback_rearm = struct {
//                 fn invoke(ud: ?*usize, _: *FS.Watcher, _: []const u8, _: u32) xev.CallbackAction {
//                     ud.?.* += 1;
//                     return .rearm;
//                 }
//             }.invoke;
//
//             var watcher: FS.Watcher = .{};
//             try fs.watch(path, &watcher, usize, &counter, callback_rearm);
//
//             fs.cancel(&watcher);
//
//             try testing.expectEqual(watcher.flags.state, .dead);
//             try testing.expectEqual(fs.active, 0);
//         }
//
//         test "test fsevents cancel with callback" {
//             var loop = try xev.Loop.init(.{});
//             defer loop.deinit();
//
//             var fs = FS.init();
//             defer fs.deinit();
//             try fs.start(&loop);
//
//             const path = "test_path_fsevents_cancel_cb";
//             _ = try std.fs.cwd().createFile(path, .{});
//             defer std.fs.cwd().deleteFile(path) catch {};
//
//             var counter: usize = 0;
//             const callback_rearm = struct {
//                 fn invoke(ud: ?*usize, _: *FS.Watcher, _: []const u8, _: u32) xev.CallbackAction {
//                     ud.?.* += 1;
//                     return .rearm;
//                 }
//             }.invoke;
//
//             var cancel_called: bool = false;
//             const cancel_callback = struct {
//                 fn invoke(ud: ?*bool, _: *FS.Watcher) void {
//                     ud.?.* = true;
//                 }
//             }.invoke;
//
//             var watcher: FS.Watcher = .{};
//             try fs.watch(path, &watcher, usize, &counter, callback_rearm);
//
//             fs.cancelWithCallback(&watcher, bool, &cancel_called, cancel_callback);
//
//             try testing.expectEqual(cancel_called, true);
//             try testing.expectEqual(watcher.flags.state, .dead);
//             try testing.expectEqual(fs.active, 0);
//         }
//     };
// }
//
// /*
//  * Copyright (c) 2014-2025 Enrico M. Crisostomo
//  *
//  * This program is free software; you can redistribute it and/or modify it under
//  * the terms of the GNU General Public License as published by the Free Software
//  * Foundation; either version 3, or (at your option) any later version.
//  *
//  * This program is distributed in the hope that it will be useful, but WITHOUT
//  * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
//  * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
//  * details.
//  *
//  * You should have received a copy of the GNU General Public License along with
//  * this program.  If not, see <http://www.gnu.org/licenses/>.
//  */
// #include <libfswatch/libfswatch_config.h>
// #include <memory>
// #include <unistd.h> // isatty()
// #include <cstdio> // fileno()
// #include <thread>
// #include "fsevents_monitor.hpp"
// #include "libfswatch/gettext_defs.h"
// #include "libfswatch_exception.hpp"
// #include "libfswatch/c/libfswatch_log.h"
// #include <mutex>
//
// namespace fsw
// {
//   using std::vector;
//   using std::string;
//
//   using FSEventFlagType =
//     struct FSEventFlagType
//     {
//       FSEventStreamEventFlags flag;
//       fsw_event_flag type;
//     };
//
//   class fsevents_monitor::Impl
//   {
//   public:
//     Impl() = default;
//     ~Impl() = default;
//
//     Impl(const Impl&) = delete;
//     Impl& operator=(const Impl&) = delete;
//
//     FSEventStreamRef stream = nullptr;
// #ifdef HAVE_MACOS_GE_10_6
//     dispatch_queue_t fsevents_queue = nullptr;
// #else
//     CFRunLoopRef run_loop = nullptr;
// #endif
//   };
//
//   static vector<FSEventFlagType> create_flag_type_vector()
//   {
//     vector<FSEventFlagType> flags;
// #ifdef HAVE_MACOS_GE_10_5
//     flags.push_back({kFSEventStreamEventFlagNone, fsw_event_flag::PlatformSpecific});
//     flags.push_back({kFSEventStreamEventFlagMustScanSubDirs, fsw_event_flag::PlatformSpecific});
//     flags.push_back({kFSEventStreamEventFlagUserDropped, fsw_event_flag::PlatformSpecific});
//     flags.push_back({kFSEventStreamEventFlagKernelDropped, fsw_event_flag::PlatformSpecific});
//     flags.push_back({kFSEventStreamEventFlagEventIdsWrapped, fsw_event_flag::PlatformSpecific});
//     flags.push_back({kFSEventStreamEventFlagHistoryDone, fsw_event_flag::PlatformSpecific});
//     flags.push_back({kFSEventStreamEventFlagRootChanged, fsw_event_flag::PlatformSpecific});
//     flags.push_back({kFSEventStreamEventFlagMount, fsw_event_flag::PlatformSpecific});
//     flags.push_back({kFSEventStreamEventFlagUnmount, fsw_event_flag::PlatformSpecific});
// #endif
//
// #ifdef HAVE_MACOS_GE_10_7
//     flags.push_back({kFSEventStreamEventFlagItemChangeOwner, fsw_event_flag::OwnerModified});
//     flags.push_back({kFSEventStreamEventFlagItemCreated, fsw_event_flag::Created});
//     flags.push_back({kFSEventStreamEventFlagItemFinderInfoMod, fsw_event_flag::PlatformSpecific});
//     flags.push_back({kFSEventStreamEventFlagItemFinderInfoMod, fsw_event_flag::AttributeModified});
//     flags.push_back({kFSEventStreamEventFlagItemInodeMetaMod, fsw_event_flag::AttributeModified});
//     flags.push_back({kFSEventStreamEventFlagItemIsDir, fsw_event_flag::IsDir});
//     flags.push_back({kFSEventStreamEventFlagItemIsFile, fsw_event_flag::IsFile});
//     flags.push_back({kFSEventStreamEventFlagItemIsSymlink, fsw_event_flag::IsSymLink});
//     flags.push_back({kFSEventStreamEventFlagItemModified, fsw_event_flag::Updated});
//     flags.push_back({kFSEventStreamEventFlagItemRemoved, fsw_event_flag::Removed});
//     flags.push_back({kFSEventStreamEventFlagItemRenamed, fsw_event_flag::Renamed});
//     flags.push_back({kFSEventStreamEventFlagItemXattrMod, fsw_event_flag::AttributeModified});
// #endif
//
// #ifdef HAVE_MACOS_GE_10_9
//     flags.push_back({kFSEventStreamEventFlagOwnEvent, fsw_event_flag::AttributeModified});
// #endif
//
// #ifdef HAVE_MACOS_GE_10_10
//     flags.push_back({kFSEventStreamEventFlagItemIsHardlink, fsw_event_flag::Link});
//     flags.push_back({kFSEventStreamEventFlagItemIsLastHardlink, fsw_event_flag::Link});
//     flags.push_back({kFSEventStreamEventFlagItemIsLastHardlink, fsw_event_flag::PlatformSpecific});
// #endif
//
// #ifdef HAVE_MACOS_GE_10_13
//     flags.push_back({kFSEventStreamEventFlagItemCloned, fsw_event_flag::PlatformSpecific});
// #endif
//
//     return flags;
//   }
//
//   static const vector<FSEventFlagType> event_flag_type = create_flag_type_vector();
//
//   fsevents_monitor::fsevents_monitor(vector<string> paths_to_monitor,
//                                      FSW_EVENT_CALLBACK *callback,
//                                      void *context) :
//     monitor(std::move(paths_to_monitor), callback, context), pImpl(std::make_unique<Impl>())
//   {
//   }
//
//   void fsevents_monitor::run()
//   {
//     std::unique_lock<std::mutex> run_loop_lock(run_mutex);
//
//     if (pImpl->stream) return;
//
//     // parsing paths
//     vector<CFStringRef> dirs;
//
//     for (const string& path : paths)
//     {
//       dirs.push_back(CFStringCreateWithCString(nullptr,
//                                                path.c_str(),
//                                                kCFStringEncodingUTF8));
//     }
//
//     if (dirs.empty()) return;
//
//     CFArrayRef pathsToWatch =
//       CFArrayCreate(nullptr,
//                     reinterpret_cast<const void **> (&dirs[0]),
//                     dirs.size(),
//                     &kCFTypeArrayCallBacks);
//
//     create_stream(pathsToWatch);
//
//     if (!pImpl->stream)
//       throw libfsw_exception(_("Event stream could not be created."));
//
// #ifdef HAVE_MACOS_GE_10_6
//     // Creating dispatch queue
//     pImpl->fsevents_queue = dispatch_queue_create("fswatch_event_queue", nullptr);
//     FSEventStreamSetDispatchQueue(pImpl->stream, pImpl->fsevents_queue);
// #else
//     // Fire the event loop
//     pImpl->run_loop = CFRunLoopGetCurrent();
//
//     // Loop Initialization
//     FSW_ELOG(_("Scheduling stream with run loop...\n"));
//     FSEventStreamScheduleWithRunLoop(pImpl->stream,
//                                      pImpl->run_loop,
//                                      kCFRunLoopDefaultMode);
// #endif
//
//     FSW_ELOG(_("Starting event stream...\n"));
//     FSEventStreamStart(pImpl->stream);
//
//     run_loop_lock.unlock();
//
// #ifdef HAVE_MACOS_GE_10_6
//     for(;;)
//     {
//       run_loop_lock.lock();
//       if (should_stop) break;
//       run_loop_lock.unlock();
//
//       std::this_thread::sleep_for(std::chrono::milliseconds((long long) (latency * 1000)));
//     }
// #else
//     // Loop
//     FSW_ELOG(_("Starting run loop...\n"));
//     CFRunLoopRun();
// #endif
//
//     // Deinitialization part
//     FSW_ELOG(_("Stopping event stream...\n"));
//     FSEventStreamStop(pImpl->stream);
//
//     FSW_ELOG(_("Invalidating event stream...\n"));
//     FSEventStreamInvalidate(pImpl->stream);
//
//     FSW_ELOG(_("Releasing event stream...\n"));
//     FSEventStreamRelease(pImpl->stream);
//
// #ifdef HAVE_MACOS_GE_10_6
//     dispatch_release(pImpl->fsevents_queue);
// #endif
//     pImpl->stream = nullptr;
//   }
//
//   /*
//    * on_stop() is designed to be invoked with a lock on the run_mutex.
//    */
//   void fsevents_monitor::on_stop()
//   {
// #ifndef HAVE_MACOS_GE_10_6
//     if (!pImpl->run_loop) throw libfsw_exception(_("run loop is null"));
//
//     FSW_ELOG(_("Stopping run loop...\n"));
//     CFRunLoopStop(pImpl->run_loop);
//
//     pImpl->run_loop = nullptr;
// #endif
//   }
//
//   static vector<fsw_event_flag> decode_flags(FSEventStreamEventFlags flag)
//   {
//     vector<fsw_event_flag> evt_flags;
//
//     for (const FSEventFlagType& type : event_flag_type)
//     {
//       if (flag & type.flag)
//       {
//         evt_flags.push_back(type.type);
//       }
//     }
//
//     return evt_flags;
//   }
//
//   void fsevents_monitor::fsevents_callback(ConstFSEventStreamRef,
//                                            void *clientCallBackInfo,
//                                            size_t numEvents,
//                                            void *eventPaths,
//                                            const FSEventStreamEventFlags eventFlags[],
//                                            const FSEventStreamEventId *)
//   {
//     const auto *fse_monitor = static_cast<fsevents_monitor *> (clientCallBackInfo);
//
//     if (!fse_monitor)
//     {
//       throw libfsw_exception(_("The callback info cannot be cast to fsevents_monitor."));
//     }
//
//     // Build the notification objects.
//     vector<event> events;
//
//     time_t curr_time;
//     time(&curr_time);
//
//     for (size_t i = 0; i < numEvents; ++i)
//     {
// #ifdef HAVE_MACOS_GE_10_13
//       auto path_info_dict = static_cast<CFDictionaryRef>(CFArrayGetValueAtIndex((CFArrayRef) eventPaths,
//                                                                                 i));
//       auto path = static_cast<CFStringRef>(CFDictionaryGetValue(path_info_dict,
//                                                                 kFSEventStreamEventExtendedDataPathKey));
//       auto cf_inode = static_cast<CFNumberRef>(CFDictionaryGetValue(path_info_dict,
//                                                                     kFSEventStreamEventExtendedFileIDKey));
//
//       // Get the length of the UTF8-encoded CFString in bytes
//       CFIndex length = CFStringGetLength(path);
//       CFIndex max_path_size = CFStringGetMaximumSizeForEncoding(length, kCFStringEncodingUTF8) + 1;
//
//       // Allocate a buffer dynamically
//       std::vector<char> path_buffer(max_path_size);
//       if (!CFStringGetCString(path, path_buffer.data(), max_path_size, kCFStringEncodingUTF8))
//       {
//           std::cerr << "Warning: Failed to convert CFStringRef to C string." << std::endl;
//           continue;
//       }
//
//       unsigned long inode;
//       CFNumberGetValue(cf_inode, kCFNumberLongType, &inode);
//       events.emplace_back(std::string(path_buffer.data()),
//                           curr_time,
//                           decode_flags(eventFlags[i]),
//                           inode);
//
// #else
//       events.emplace_back(((char **) eventPaths)[i],
//                           curr_time,
//                           decode_flags(eventFlags[i]));
// #endif
//     }
//
//     if (!events.empty())
//     {
//       fse_monitor->notify_events(events);
//     }
//   }
//
//   bool fsevents_monitor::no_defer()
//   {
//     string no_defer = get_property(DARWIN_EVENTSTREAM_NO_DEFER);
//
//     if (no_defer.empty())
//       return (!isatty(fileno(stdin)));
//
//     return (no_defer == "true");
//   }
//
//   void fsevents_monitor::create_stream(CFArrayRef pathsToWatch)
//   {
//     auto context = std::make_unique<FSEventStreamContext>();
//     context->version = 0;
//     context->info = this;
//     context->retain = nullptr;
//     context->release = nullptr;
//     context->copyDescription = nullptr;
//
//     FSEventStreamCreateFlags streamFlags = kFSEventStreamCreateFlagNone;
//     if (this->no_defer()) streamFlags |= kFSEventStreamCreateFlagNoDefer;
// #ifdef HAVE_MACOS_GE_10_7
//     streamFlags |= kFSEventStreamCreateFlagFileEvents;
// #endif
//
// #ifdef HAVE_MACOS_GE_10_13
//     streamFlags |= kFSEventStreamCreateFlagUseExtendedData;
//     streamFlags |= kFSEventStreamCreateFlagUseCFTypes;
// #endif
//
//     FSW_ELOG(_("Creating FSEvent stream...\n"));
//     pImpl->stream = FSEventStreamCreate(nullptr,
//                                  &fsevents_monitor::fsevents_callback,
//                                  context.get(),
//                                  pathsToWatch,
//                                  kFSEventStreamEventIdSinceNow,
//                                  latency,
//                                  streamFlags);
//   }
// }
