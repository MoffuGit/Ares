const std = @import("std");
const core = @import("core");
const tui = @import("tui");

const Allocator = std.mem.Allocator;
const App = tui.App;
const EventListeners = tui.EventListeners;

pub const KeymapActionEvent = struct {
    action: core.Action,
    consumed: bool = false,

    pub fn consume(self: *KeymapActionEvent) void {
        self.consumed = true;
    }
};

pub const EventType = enum {
    worktree_updated,
    buffer_updated,
    settings_changed,
    keymap_actions,
};

pub const EventData = union(EventType) {
    worktree_updated: *core.worktree.UpdatedEntriesSet,
    buffer_updated: u64,
    settings_changed: void,
    keymap_actions: *KeymapActionEvent,
};

pub const Subscribers = EventListeners(EventType, EventData);

const Bridge = @This();

engine: *core.Engine,
app: *App,
subs: Subscribers = .{},
alloc: Allocator,

pub fn init(alloc: Allocator, engine: *core.Engine, app: *App) Bridge {
    return .{
        .alloc = alloc,
        .engine = engine,
        .app = app,
    };
}

pub fn deinit(self: *Bridge) void {
    self.subs.deinit(self.alloc);
}

pub fn drainEngineEvents(self: *Bridge) void {
    var had_event = false;
    while (self.engine.pollEvent()) |event| {
        had_event = true;
        switch (event) {
            .worktree_updated => |entries| {
                self.subs.notify(.worktree_updated, .{ .worktree_updated = entries });
            },
            .buffer_updated => |id| {
                self.subs.notify(.buffer_updated, .{ .buffer_updated = id });
            },
            .settings_changed => {
                self.subs.notify(.settings_changed, .{ .settings_changed = {} });
            },
            .keymap_actions => |actions| {
                self.dispatchKeymapActions(actions);
            },
        }
    }
    if (had_event) self.app.requestDraw();
}

pub fn dispatchKeymapActions(self: *Bridge, actions: []const core.Action) void {
    var ev = KeymapActionEvent{ .action = undefined };
    for (actions) |action| {
        ev.action = action;
        ev.consumed = false;
        self.subs.notifyConsumableReverse(.keymap_actions, .{ .keymap_actions = &ev }, &ev.consumed);
    }
}

pub fn dispatch(self: *Bridge, cmd: core.Command) void {
    self.engine.dispatch(cmd);
}

pub fn subscribe(
    self: *Bridge,
    event: EventType,
    comptime Userdata: type,
    userdata: *Userdata,
    comptime cb: *const fn (userdata: *Userdata, data: EventData) void,
) !u64 {
    return self.subs.addSubscription(self.alloc, event, Userdata, userdata, cb);
}

pub fn unsubscribe(self: *Bridge, event: EventType, id: u64) void {
    self.subs.removeSubscription(event, id);
}
