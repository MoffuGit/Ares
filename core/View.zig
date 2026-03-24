const std = @import("std");
const objc = @import("objc");
const Allocator = std.mem.Allocator;
const Editor = @import("editor/Editor.zig");
const Renderer = @import("Renderer.zig");
const RendererThread = @import("renderer/Thread.zig");
const fontpkg = @import("font/mod.zig");
const Grid = fontpkg.Grid;
const SharedState = @import("SharedState.zig");
const log = std.log.scoped(.view);
const Project = @import("Project.zig");

const View = @This();

pub const Kind = enum(u8) {
    editor = 0,
    terminal = 1,
};

pub const Content = union(Kind) {
    editor: *Editor,
    terminal: struct {
        id: usize = 1,
    },
};

alloc: Allocator,
content: Content,

grid: Grid,

renderer: Renderer,
renderer_thread: RendererThread,
renderer_thr: std.Thread,

shared_state: SharedState,

pub fn create(project: *Project, alloc: Allocator, kind: Kind, layer_ptr: *anyopaque) !*View {
    const metal_layer = objc.Object.fromId(layer_ptr);

    const view = try alloc.create(View);
    errdefer alloc.destroy(view);

    var grid = try Grid.init(alloc, .{ .size = .{
        .points = 12,
    } });
    errdefer grid.deinit(alloc);

    var renderer = try Renderer.init(
        alloc,
        .{ .grid = &view.grid, .metal_layer = metal_layer, .size = .{
            .screen = .{ .height = 0, .width = 0 },
            .cell = grid.cellSize(),
        } },
    );
    errdefer renderer.deinit();

    var renderer_thread = try RendererThread.init(alloc, &view.renderer, &view.shared_state);
    errdefer renderer_thread.deinit();

    var shared_state = try SharedState.init(alloc, .{ .screen = .{ .height = 0, .width = 0 }, .cell = grid.cellSize() });
    errdefer shared_state.deinit();

    view.* = .{
        .grid = grid,
        .alloc = alloc,
        .shared_state = shared_state,
        .content = switch (kind) {
            .editor => .{ .editor = try Editor.create(project, alloc, &view.renderer_thread, &view.shared_state) },
            .terminal => .{ .terminal = .{} },
        },
        .renderer = renderer,
        .renderer_thread = renderer_thread,
        .renderer_thr = undefined,
    };

    view.renderer_thr = try std.Thread.spawn(.{}, RendererThread.threadMain, .{&view.renderer_thread});

    return view;
}

pub fn resize(self: *View, width: u32, height: u32) void {
    switch (self.content) {
        .editor => |editor| {
            editor.resize(.{ .screen = .{ .height = height, .width = width }, .cell = self.grid.cellSize() });
        },
        else => {},
    }
    _ = self.renderer_thread.mailbox.push(.{ .resize = .{ .height = height, .width = width } }, .instant);
    self.renderer_thread.wakeup.notify() catch {};
}

pub fn setVisibility(self: *View, visible: bool) !void {
    _ = self.renderer_thread.mailbox.push(.{ .visible = visible }, .instant);
    self.renderer_thread.wakeup.notify() catch {};
}

pub fn destroy(self: *View) void {
    {
        self.renderer_thread.stop.notify() catch |err|
            log.err("error notifying renderer thread to stop, may stall err={}", .{err});
        self.renderer_thr.join();
    }

    self.renderer_thread.deinit();

    self.renderer.deinit();
    self.grid.deinit(self.alloc);

    self.shared_state.deinit();

    switch (self.content) {
        .editor => |editor| {
            editor.destroy();
        },
        else => {},
    }

    self.alloc.destroy(self);
}
