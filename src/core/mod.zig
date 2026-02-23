const std = @import("std");
const Allocator = std.mem.Allocator;

pub const EventQueue = @import("EventQueue.zig");
pub const Waker = @import("Waker.zig");
pub const Project = @import("project/Project.zig");
pub const Settings = @import("settings/mod.zig");
pub const Resolver = @import("keymaps/Resolver.zig");
pub const keymaps = @import("keymaps/mod.zig");
pub const KeyStroke = @import("keymaps/KeyStroke.zig");
pub const worktree = @import("worktree/mod.zig");
pub const BufferStore = @import("buffer/BufferStore.zig");
pub const Buffer = @import("buffer/Buffer.zig");
pub const Theme = @import("settings/theme/mod.zig");

pub const Mode = keymaps.Mode;
pub const Action = keymaps.Action;
pub const Event = EventQueue.Event;

pub const Command = union(enum) {
    open_project: []const u8,
    close_project: void,
    open_file: u64,
    key_stroke: KeyStroke.KeyStroke,
    set_mode: Mode,
    set_scheme: Settings.Scheme,
    set_system_scheme: Settings.ColorScheme,
    reload_settings: []const u8,
    tick: i64,
};

pub const Engine = @This();

alloc: Allocator,
events: EventQueue,
mode: Mode = .normal,
settings: *Settings,
resolver: *Resolver,
project: ?*Project = null,

pub fn create(alloc: Allocator, waker: Waker) !*Engine {
    const engine = try alloc.create(Engine);
    errdefer alloc.destroy(engine);

    var events = try EventQueue.init(alloc, waker);
    errdefer events.deinit();

    const settings = try Settings.create(alloc);
    errdefer settings.destroy();

    const resolver = try Resolver.create(alloc, &engine.events);
    errdefer resolver.destroy();

    engine.* = .{
        .alloc = alloc,
        .events = events,
        .settings = settings,
        .resolver = resolver,
    };

    return engine;
}

pub fn destroy(self: *Engine) void {
    if (self.project) |p| p.destroy(self.alloc);
    self.resolver.destroy();
    self.settings.destroy();
    self.events.deinit();
    self.alloc.destroy(self);
}

pub fn dispatch(self: *Engine, cmd: Command) void {
    switch (cmd) {
        .open_project => |path| {
            if (self.project) |p| p.destroy(self.alloc);
            self.project = Project.create(self.alloc, path, &self.events) catch null;
        },
        .close_project => {
            if (self.project) |p| {
                p.destroy(self.alloc);
                self.project = null;
            }
        },
        .open_file => |entry_id| {
            if (self.project) |p| {
                _ = p.buffer_store.open(entry_id);
            }
        },
        .key_stroke => |ks| {
            self.resolver.feedKeyStroke(self.mode, &self.settings.keymaps, ks);
        },
        .set_mode => |mode| {
            self.mode = mode;
        },
        .set_scheme => |scheme| {
            self.settings.scheme = scheme;
            self.settings.applyTheme();
            self.events.push(.{ .settings_changed = {} });
        },
        .set_system_scheme => |scheme| {
            self.settings.setSystemScheme(scheme);
            self.events.push(.{ .settings_changed = {} });
        },
        .reload_settings => |path| {
            self.settings.load(path) catch {};
            self.events.push(.{ .settings_changed = {} });
        },
        .tick => |now_us| {
            self.resolver.tick(now_us);
        },
    }
}

pub fn pollEvent(self: *Engine) ?Event {
    return self.events.poll();
}
