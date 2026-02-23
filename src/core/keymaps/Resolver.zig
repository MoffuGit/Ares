const std = @import("std");
const triepkg = @import("datastruct");
const keystrokepkg = @import("KeyStroke.zig");
const keymapspkg = @import("mod.zig");
const EventQueue = @import("../EventQueue.zig");

const KeyStroke = keystrokepkg.KeyStroke;
const KeyStrokeContext = keystrokepkg.KeyStrokeContext;
const Action = keymapspkg.Action;
const Keymaps = keymapspkg.Keymaps;
const Mode = keymapspkg.Mode;
const Node = triepkg.NodeType(KeyStroke, Action, KeyStrokeContext);

const Allocator = std.mem.Allocator;

const Resolver = @This();

const flush_timeout_us: i64 = 500_000;

alloc: Allocator,
events: *EventQueue,
node: ?*Node = null,
last_mode: Mode,
flush_deadline: ?i64 = null,

pub fn create(alloc: Allocator, events: *EventQueue) !*Resolver {
    const resolver = try alloc.create(Resolver);

    resolver.* = .{
        .alloc = alloc,
        .events = events,
        .last_mode = .normal,
    };

    return resolver;
}

pub fn destroy(self: *Resolver) void {
    self.alloc.destroy(self);
}

pub fn feedKeyStroke(self: *Resolver, mode: Mode, keymaps: *Keymaps, ks: KeyStroke) void {
    if (self.last_mode != mode) {
        self.reset();
        self.last_mode = mode;
    }

    const trie = keymaps.actions(mode);
    var cur: *Node = self.node orelse trie.root;

    if (cur.childrens.get(ks)) |child| {
        return self.consumeChild(child);
    }

    if (cur != trie.root) {
        if (cur.values.items.len > 0) {
            self.dispatchActions(cur.values.items);
        }
        self.reset();
        cur = trie.root;

        if (cur.childrens.get(ks)) |child| {
            return self.consumeChild(child);
        }
    }

    self.reset();
}

pub fn tick(self: *Resolver, now_us: i64) void {
    if (self.flush_deadline) |deadline| {
        if (now_us >= deadline) {
            self.flush();
        }
    }
}

pub fn flush(self: *Resolver) void {
    if (self.node) |n| {
        if (n.values.items.len > 0) {
            self.dispatchActions(n.values.items);
        }
    }
    self.reset();
}

pub fn reset(self: *Resolver) void {
    self.node = null;
    self.flush_deadline = null;
}

fn consumeChild(self: *Resolver, child: *Node) void {
    if (child.childrens.count() != 0) {
        self.node = child;
        self.flush_deadline = std.time.microTimestamp() + flush_timeout_us;
        return;
    }

    if (child.values.items.len > 0) {
        self.reset();
        self.dispatchActions(child.values.items);
    }
}

fn dispatchActions(self: *Resolver, actions: []const Action) void {
    self.events.push(.{ .keymap_actions = actions });
}
