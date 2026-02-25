// const std = @import("std");
// const triepkg = @import("datastruct");
// const keystrokepkg = @import("KeyStroke.zig");
// const keymapspkg = @import("mod.zig");
// const EventQueue = @import("../EventQueue.zig");
//
// const KeyStroke = keystrokepkg.KeyStroke;
// const KeyStrokeContext = keystrokepkg.KeyStrokeContext;
// const Action = keymapspkg.Action;
// const Keymaps = keymapspkg.Keymaps;
// const Mode = keymapspkg.Mode;
// const Node = triepkg.NodeType(KeyStroke, Action, KeyStrokeContext);
//
// const Allocator = std.mem.Allocator;
//
// const Resolver = @This();
//
// const flush_timeout_us: i64 = 500_000;
//
// alloc: Allocator,
// events: *EventQueue,
// node: ?*Node = null,
// last_mode: Mode,
//
// mutex: std.Thread.Mutex = .{},
// cond: std.Thread.Condition = .{},
// deadline: ?i64 = null,
// timer_thread: ?std.Thread = null,
// running: bool = true,
//
// pub fn create(alloc: Allocator, events: *EventQueue) !*Resolver {
//     const resolver = try alloc.create(Resolver);
//
//     resolver.* = .{
//         .alloc = alloc,
//         .events = events,
//         .last_mode = .normal,
//     };
//
//     resolver.timer_thread = std.Thread.spawn(.{}, timerLoop, .{resolver}) catch null;
//
//     return resolver;
// }
//
// pub fn destroy(self: *Resolver) void {
//     {
//         self.mutex.lock();
//         defer self.mutex.unlock();
//         self.running = false;
//         self.cond.signal();
//     }
//     if (self.timer_thread) |t| t.join();
//     self.alloc.destroy(self);
// }
//
// pub fn feedKeyStroke(self: *Resolver, mode: Mode, keymaps: *Keymaps, ks: KeyStroke) void {
//     self.mutex.lock();
//     defer self.mutex.unlock();
//
//     if (self.last_mode != mode) {
//         self.resetLocked();
//         self.last_mode = mode;
//     }
//
//     const trie = keymaps.actions(mode);
//     var cur: *Node = self.node orelse trie.root;
//
//     const maybe = cur.childrens.get(ks);
//
//     if (maybe) |child| {
//         return self.consumeChild(child);
//     }
//
//     if (cur != trie.root) {
//         if (cur.values.items.len > 0) {
//             self.dispatchActions(cur.values.items);
//         }
//         self.resetLocked();
//         cur = trie.root;
//
//         if (cur.childrens.get(ks)) |child| {
//             return self.consumeChild(child);
//         }
//     }
//
//     self.resetLocked();
// }
//
// fn flushLocked(self: *Resolver) void {
//     if (self.node) |n| {
//         if (n.values.items.len > 0) {
//             self.dispatchActions(n.values.items);
//         }
//     }
//     self.resetLocked();
// }
//
// fn resetLocked(self: *Resolver) void {
//     self.node = null;
//     self.deadline = null;
// }
//
// fn consumeChild(self: *Resolver, child: *Node) void {
//     if (child.childrens.count() != 0) {
//         self.node = child;
//         self.deadline = std.time.microTimestamp() + flush_timeout_us;
//         self.cond.signal();
//         return;
//     }
//
//     if (child.values.items.len > 0) {
//         self.resetLocked();
//         self.dispatchActions(child.values.items);
//     }
// }
//
// fn dispatchActions(self: *Resolver, actions: []const Action) void {
//     self.events.push(.{ .keymap_actions = actions });
// }
//
// fn timerLoop(self: *Resolver) void {
//     self.mutex.lock();
//     defer self.mutex.unlock();
//
//     while (self.running) {
//         if (self.deadline) |dl| {
//             const now = std.time.microTimestamp();
//             if (now >= dl) {
//                 self.flushLocked();
//             } else {
//                 const remaining_ns: u64 = @intCast((dl - now) * 1000);
//                 self.cond.timedWait(&self.mutex, remaining_ns) catch {};
//             }
//         } else {
//             self.cond.wait(&self.mutex);
//         }
//     }
// }
