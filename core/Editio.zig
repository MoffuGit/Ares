const Editio = @This();

const std = @import("std");
const globalpkg = @import("global.zig");
const global = &globalpkg.state;
const Allocator = std.mem.Allocator;
const sizepkg = @import("size.zig");
const inputpkg = @import("input.zig");
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
    try global.events.on(.bufferUpdate, .{ .ctx = thread, .handle = handleBufferUpdate });
    try global.events.on(.themeUpdate, .{ .ctx = thread, .handle = handleThemeUpdate });
}

pub fn threadExit(_: *Editio, thread: *Thread) void {
    global.events.off(.bufferUpdate, .{ .ctx = thread, .handle = handleBufferUpdate });
    global.events.off(.themeUpdate, .{ .ctx = thread, .handle = handleThemeUpdate });
}

pub fn readEditorState(self: *Editio, out: *globalpkg.ExternEditorState) bool {
    return self.state.readEditorState(out);
}

fn handleBufferUpdate(ctx: *anyopaque, event: globalpkg.GlobalEvents) void {
    const self: *Thread = @ptrCast(@alignCast(ctx));

    const data = event.bufferUpdate;

    if (self.io.state.selected_entry == data) {
        _ = self.mailbox.push(.{ .buffer_update = event.bufferUpdate }, .instant);
        self.wakeup.notify() catch {};
    }
}

fn handleThemeUpdate(ctx: *anyopaque, _: globalpkg.GlobalEvents) void {
    const self: *Thread = @ptrCast(@alignCast(ctx));

    _ = self.mailbox.push(.{ .themeUpdate = {} }, .instant);
    self.wakeup.notify() catch {};
}
