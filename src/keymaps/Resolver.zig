const std = @import("std");
const vaxis = @import("vaxis");
const triepkg = @import("../datastruct/trie.zig");
const keystrokepkg = @import("KeyStroke.zig");
const keymapspkg = @import("mod.zig");
const apppkg = @import("../app/mod.zig");
const messagepkg = @import("../app/window/message.zig");
const global = @import("../global.zig");

const KeyStroke = keystrokepkg.KeyStroke;
const KeyStrokeContext = keystrokepkg.KeyStrokeContext;
const Action = keymapspkg.Action;
const Keymaps = keymapspkg.Keymaps;
const Node = triepkg.NodeType(KeyStroke, Action, KeyStrokeContext);

const App = apppkg;
const Context = apppkg.Context;
const Element = @import("../app/window/element/mod.zig");
const EventContext = @import("../app/window/EventContext.zig");
const Tick = messagepkg.Tick;
const Allocator = std.mem.Allocator;

const Resolver = @This();

const flush_timeout_us: i64 = 500_000;

alloc: Allocator,
node: ?*Node = null,
app: *App,
last_mode: global.Mode,
generation: u64,

pub fn create(alloc: Allocator, app: *App) !*Resolver {
    const resolver = try alloc.create(Resolver);
    errdefer alloc.destroy(resolver);

    resolver.* = .{
        .alloc = alloc,
        .app = app,
        .last_mode = global.mode,
        .generation = global.settings.keymap_generation,
    };

    try app.root().addEventListener(.key_press, Resolver, resolver, onKeyPress);

    return resolver;
}

pub fn destroy(self: *Resolver) void {
    self.alloc.destroy(self);
}

fn onKeyPress(self: *Resolver, evt: Element.ElementEvent) void {
    if (evt.ctx.phase == .bubbling) return;

    const key = evt.event.key_press;
    const ks = KeyStroke{
        .codepoint = key.codepoint,
        .mods = key.mods,
    };

    self.resolve(ks);
    evt.ctx.stopPropagation();
}

pub fn resolve(
    self: *Resolver,
    ks: KeyStroke,
) void {
    const mode = global.mode;
    var keymaps = global.settings.keymaps;

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
            self.dispatchKeyMapActions(cur.values.items);
        }
        self.reset();
        cur = trie.root;

        if (cur.childrens.get(ks)) |child| {
            return self.consumeChild(child);
        }
    }

    self.reset();
}

pub fn flush(self: *Resolver) void {
    if (self.node) |n| {
        if (n.values.items.len > 0) {
            self.dispatchKeyMapActions(n.values.items);
        }
    }
    self.reset();
}

pub fn reset(self: *Resolver) void {
    self.node = null;
}

fn consumeChild(
    self: *Resolver,
    child: *Node,
) void {
    if (child.childrens.count() != 0) {
        self.node = child;
        self.armTimer();
        return;
    }

    if (child.values.items.len > 0) {
        self.reset();
        self.dispatchKeyMapActions(child.values.items);
    }
}

fn dispatchKeyMapActions(self: *Resolver, actions: []const Action) void {
    const loop = self.app.loop;
    if (loop.mailbox.push(.{ .app = .{ .keymapAction = actions } }, .instant) != 0) {
        loop.wakeup.notify() catch |err| {
            std.log.err("The key action didn't got send: {}", .{err});
        };
        std.log.debug("we send it📍", .{});
    }
}

fn armTimer(self: *Resolver) void {
    const tick = Tick{
        .next = std.time.microTimestamp() + flush_timeout_us,
        .callback = tickCallback,
        .userdata = self,
    };
    _ = self.app.loop.mailbox.push(.{ .window = .{ .tick = tick } }, .instant);
    self.app.loop.wakeup.notify() catch {};
}

fn tickCallback(userdata: ?*anyopaque, _: i64) ?Tick {
    const self: *Resolver = @ptrCast(@alignCast(userdata orelse return null));
    if (self.node == null) return null;
    self.flush();
    return null;
}
