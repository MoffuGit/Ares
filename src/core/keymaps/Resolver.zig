const std = @import("std");
const triepkg = @import("datastruct");
const keystrokepkg = @import("KeyStroke.zig");
const keymapspkg = @import("mod.zig");

const KeyStroke = keystrokepkg.KeyStroke;
const KeyStrokeContext = keystrokepkg.KeyStrokeContext;
const Action = keymapspkg.Action;
const Keymaps = keymapspkg.Keymaps;
const Mode = keymapspkg.Mode;
const Scope = keymapspkg.Scope;
const Node = triepkg.NodeType(KeyStroke, Action, KeyStrokeContext);

const Allocator = std.mem.Allocator;

const Resolver = @This();

const flush_timeout_us: i64 = 500_000;
const max_pending = 2;

alloc: Allocator,
node: ?*Node = null,
active_scope: ?Scope = null,
last_mode: Mode,
last_focus_gen: u64 = 0,
flush_deadline: ?i64 = null,
pending_results: [max_pending][]const Action = undefined,
pending_count: u8 = 0,

pub fn create(alloc: Allocator) !*Resolver {
    const resolver = try alloc.create(Resolver);

    resolver.* = .{
        .alloc = alloc,
        .last_mode = .normal,
    };

    return resolver;
}

pub fn destroy(self: *Resolver) void {
    self.alloc.destroy(self);
}

pub fn feedKeyStroke(self: *Resolver, mode: Mode, keymaps: *Keymaps, focus_stack: []const Scope, focus_gen: u64, ks: KeyStroke) void {
    if (self.last_mode != mode or self.last_focus_gen != focus_gen) {
        self.flush();
        self.last_mode = mode;
        self.last_focus_gen = focus_gen;
    }

    // If mid-sequence, try to continue in the active scope
    if (self.active_scope) |scope| {
        const trie = keymaps.actions(scope, mode);
        const cur: *Node = self.node orelse trie.root;

        if (cur.childrens.get(ks)) |child| {
            return self.consumeChild(child, scope);
        }

        // Can't continue in active scope — flush current values
        if (cur.values.items.len > 0) {
            self.pushResult(cur.values.items);
        }
        self.reset();
    }

    // Try each scope in priority order from root
    for (focus_stack) |scope| {
        const trie = keymaps.actions(scope, mode);
        if (trie.root.childrens.get(ks)) |child| {
            return self.consumeChild(child, scope);
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

pub fn pollResult(self: *Resolver) ?[]const Action {
    if (self.pending_count == 0) return null;
    const result = self.pending_results[0];
    self.pending_count -= 1;
    if (self.pending_count > 0) {
        self.pending_results[0] = self.pending_results[1];
    }
    return result;
}

pub fn flush(self: *Resolver) void {
    if (self.node) |n| {
        if (n.values.items.len > 0) {
            self.pushResult(n.values.items);
        }
    }
    self.reset();
}

pub fn reset(self: *Resolver) void {
    self.node = null;
    self.active_scope = null;
    self.flush_deadline = null;
}

fn consumeChild(self: *Resolver, child: *Node, scope: Scope) void {
    if (child.childrens.count() != 0) {
        self.node = child;
        self.active_scope = scope;
        self.flush_deadline = std.time.microTimestamp() + flush_timeout_us;
        return;
    }

    if (child.values.items.len > 0) {
        self.pushResult(child.values.items);
    }
    self.reset();
}

fn pushResult(self: *Resolver, actions: []const Action) void {
    if (self.pending_count < max_pending) {
        self.pending_results[self.pending_count] = actions;
        self.pending_count += 1;
    }
}
