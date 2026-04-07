const Editor = @This();

const std = @import("std");
const globalpkg = @import("global.zig");
const global = &globalpkg.state;
const Allocator = std.mem.Allocator;
const sizepkg = @import("size.zig");
const Project = @import("Project.zig");
const Editio = @import("Editio.zig");
const SurfacePkg = @import("Surface.zig");
const App = @import("App.zig");

const EditorSurface = SurfacePkg.Surface(Editio);

alloc: Allocator,
surface: *EditorSurface,

pub fn create(app: *App, project: *Project, alloc: Allocator, layer_ptr: *anyopaque, width: u32, height: u32) !*Editor {
    const self = try alloc.create(Editor);
    errdefer alloc.destroy(self);

    const surface = try EditorSurface.create(alloc, &app.grid, layer_ptr, .{ .width = width, .height = height }, .{
        .project = project,
    });
    errdefer surface.destroy();

    self.* = .{
        .alloc = alloc,
        .surface = surface,
    };

    self.surface.io.syncTextColor();

    try global.events.on(.bufferUpdate, .{ .ctx = self, .handle = onBufferUpdate });
    errdefer global.events.off(.bufferUpdate, .{ .ctx = self, .handle = onBufferUpdate });

    try global.events.on(.themeUpdate, .{ .ctx = self, .handle = onThemeUpdate });
    errdefer global.events.off(.themeUpdate, .{ .ctx = self, .handle = onThemeUpdate });

    return self;
}

pub fn destroy(self: *Editor) void {
    global.events.off(.bufferUpdate, .{ .ctx = self, .handle = onBufferUpdate });
    global.events.off(.themeUpdate, .{ .ctx = self, .handle = onThemeUpdate });

    self.surface.destroy();
    self.alloc.destroy(self);
}

fn onBufferUpdate(ctx: *anyopaque, event: globalpkg.GlobalEvents) void {
    const self: *Editor = @ptrCast(@alignCast(ctx));

    self.surface.sendIo(.{ .buffer_update = event.bufferUpdate });
}

fn onThemeUpdate(ctx: *anyopaque, _: globalpkg.GlobalEvents) void {
    const self: *Editor = @ptrCast(@alignCast(ctx));
    self.surface.sendIo(.{ .theme_update = {} });
}

pub fn resize(self: *Editor, size: sizepkg.ScreenSize) void {
    self.surface.resize(size);
}

pub fn selectEntry(self: *Editor, id: u64) void {
    self.surface.sendIo(.{ .select_entry = id });
}

pub fn scrollTo(self: *Editor, row: u64) void {
    self.surface.sendIo(.{ .scroll = row });
}

pub fn readSurfaceState(self: *Editor, out: *globalpkg.ExternSurfaceState) void {
    self.surface.readSurfaceState(out);
}

pub fn readEditorState(self: *Editor, out: *globalpkg.ExternEditorState) bool {
    return self.surface.io.readEditorState(out);
}

pub fn setVisibility(self: *Editor, visible: bool) !void {
    try self.surface.setVisibility(visible);
}
