const Editio = @This();

const std = @import("std");
const globalpkg = @import("global.zig");
const global = &globalpkg.state;
const Allocator = std.mem.Allocator;
const sizepkg = @import("size.zig");
const Project = @import("Project.zig");
const Renderer = @import("Renderer.zig");
const RendererThread = @import("renderer/Thread.zig");
const Grid = @import("font/mod.zig").Grid;
const Editor = @import("Editor.zig");

pub const Thread = @import("editio/Thread.zig").Thread;

const log = std.log.scoped(.editio);

alloc: Allocator,
grid: *Grid,
renderer: *Renderer,
renderer_thread: *RendererThread,
state: *Editor,

pub fn init(
    alloc: Allocator,
    grid: *Grid,
    renderer: *Renderer,
    renderer_thread: *RendererThread,
    _: sizepkg.ScreenSize,
    state: *Editor,
) !Editio {
    return .{
        .alloc = alloc,
        .grid = grid,
        .renderer = renderer,
        .renderer_thread = renderer_thread,
        .state = state,
    };
}

pub fn deinit(self: *Editio) void {
    _ = self;
}

pub fn threadEnter(_: *Editio, thread: *Thread) !void {
    try global.events.on(.bufferUpdate, .{ .ctx = thread, .handle = handleBufferUpdateEvent });
    errdefer global.events.off(.bufferUpdate, .{ .ctx = thread, .handle = handleBufferUpdateEvent });
}

pub fn threadExit(_: *Editio, thread: *Thread) void {
    global.events.off(.bufferUpdate, .{ .ctx = thread, .handle = handleBufferUpdateEvent });
}

pub fn resize(self: *Editio, size: sizepkg.ScreenSize) void {
    self.state.resize(size);

    _ = self.renderer_thread.mailbox.push(.{ .resize = size }, .instant);
}

pub fn selectEntry(self: *Editio, id: u64) void {
    self.state.selectEntry(id);
}

pub fn scroll(self: *Editio, row: u64) void {
    self.state.scroll(row);
}

pub fn onBufferUpdate(self: *Editio, entry_id: u64) void {
    self.state.onBufferUpdate(entry_id);
}

pub fn readEditorState(self: *Editio, out: *globalpkg.ExternEditorState) bool {
    return self.state.readEditorState(out);
}

fn handleBufferUpdateEvent(ctx: *anyopaque, event: globalpkg.GlobalEvents) void {
    const self: *Thread = @ptrCast(@alignCast(ctx));

    _ = self.mailbox.push(.{ .buffer_update = event.bufferUpdate }, .instant);
    self.wakeup.notify() catch {};
}
