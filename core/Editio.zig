const Editio = @This();

const std = @import("std");
const globalpkg = @import("global.zig");
const global = &globalpkg.state;
const Allocator = std.mem.Allocator;
const SharedState = @import("SharedState.zig");
const sizepkg = @import("size.zig");
const Project = @import("Project.zig");
const Renderer = @import("Renderer.zig");
const RendererThread = @import("renderer/Thread.zig");
const Grid = @import("font/mod.zig").Grid;
const Editor = @import("Editor.zig");

pub const Thread = @import("editio/Thread.zig").Thread;

const log = std.log.scoped(.editio);

pub const InitConfig = struct {
    project: *Project,
};

alloc: Allocator,
grid: *Grid,
shared_state: *SharedState,
renderer: *Renderer,
renderer_thread: *RendererThread,
editor: Editor,

pub fn init(
    alloc: Allocator,
    grid: *Grid,
    shared_state: *SharedState,
    renderer: *Renderer,
    renderer_thread: *RendererThread,
    _: sizepkg.ScreenSize,
    config: InitConfig,
) !Editio {
    return .{
        .alloc = alloc,
        .grid = grid,
        .shared_state = shared_state,
        .renderer = renderer,
        .renderer_thread = renderer_thread,
        .editor = Editor.init(alloc, config.project, shared_state, renderer),
    };
}

pub fn deinit(self: *Editio) void {
    _ = self;
}

pub fn threadEnter(self: *Editio, thread: *Thread) !void {
    self.editor.syncTextColor();

    try global.events.on(.bufferUpdate, .{ .ctx = thread, .handle = handleBufferUpdateEvent });
    errdefer global.events.off(.bufferUpdate, .{ .ctx = thread, .handle = handleBufferUpdateEvent });

    try global.events.on(.themeUpdate, .{ .ctx = thread, .handle = handleThemeUpdateEvent });
    errdefer global.events.off(.themeUpdate, .{ .ctx = thread, .handle = handleThemeUpdateEvent });
}

pub fn threadExit(_: *Editio, thread: *Thread) void {
    global.events.off(.bufferUpdate, .{ .ctx = thread, .handle = handleBufferUpdateEvent });
    global.events.off(.themeUpdate, .{ .ctx = thread, .handle = handleThemeUpdateEvent });
}

pub fn resize(self: *Editio, size: sizepkg.ScreenSize) void {
    {
        self.shared_state.mutex.lock();
        defer self.shared_state.mutex.unlock();

        self.shared_state.screen.resize(.{
            .screen = size,
            .cell = self.grid.cellSize(),
        });
    }

    self.editor.writeScreen();

    _ = self.renderer_thread.mailbox.push(.{ .resize = size }, .instant);
    self.renderer_thread.wakeup.notify() catch {};
}

pub fn selectEntry(self: *Editio, id: u64) void {
    self.editor.selectEntry(id);
    self.editor.writeScreen();
    self.renderer_thread.wakeup.notify() catch {};
}

pub fn scroll(self: *Editio, row: u64) void {
    self.editor.scroll(row);
    self.editor.writeScreen();
    self.renderer_thread.wakeup.notify() catch {};
}

pub fn onBufferUpdate(self: *Editio, entry_id: u64) void {
    self.editor.onBufferUpdate(entry_id);
    self.editor.writeScreen();
    self.renderer_thread.wakeup.notify() catch {};
}

pub fn onThemeUpdate(self: *Editio) void {
    self.editor.onThemeUpdate();
}

pub fn readEditorState(self: *Editio, out: *globalpkg.ExternEditorState) bool {
    return self.editor.readEditorState(out);
}

fn handleBufferUpdateEvent(ctx: *anyopaque, event: globalpkg.GlobalEvents) void {
    const self: *Thread = @ptrCast(@alignCast(ctx));

    _ = self.mailbox.push(.{ .buffer_update = event.bufferUpdate }, .instant);
    self.wakeup.notify() catch {};
}

fn handleThemeUpdateEvent(ctx: *anyopaque, _: globalpkg.GlobalEvents) void {
    const self: *Thread = @ptrCast(@alignCast(ctx));

    _ = self.mailbox.push(.{ .theme_update = {} }, .instant);
    self.wakeup.notify() catch {};
}
