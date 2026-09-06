const std = @import("std");
const heap = std.heap;
const Allocator = std.mem.Allocator;
const Io = std.Io;

const chunk_pool = @import("chunk_pool.zig");
const ChunkAllocator = chunk_pool.ChunkAllocator;
const Core = @import("core.zig");
const datastruct = @import("datastruct.zig");
const SinglyLinkedList = datastruct.SinglyLinkedList;
const Display = @import("display.zig");
const render = @import("render.zig");
const Renderer = render.Renderer;
const Handle = Renderer.Handle;
const view = @import("view.zig");
const ViewState = view.ViewState;
const win = @import("window.zig");
const Window = win.Window;

const log = std.log.scoped(.app);

pub const App = @This();

io: Io,
gpa: Allocator,
arena: heap.ArenaAllocator,
chunks: ChunkAllocator,
core: Core,
display: Display,
renderer: Renderer,
states: SinglyLinkedList(WindowState),

pub fn init(self: *App, gpa: Allocator, io: Io) !void {
    self.* = .{
        .arena = .init(gpa),
        .chunks = undefined,
        .io = io,
        .gpa = gpa,
        .states = .empty,
        .renderer = undefined,
        .core = undefined,
        .display = undefined,
    };

    const arena = self.arena.allocator();
    errdefer self.arena.deinit();

    try self.chunks.init(arena, &.{
        .{
            .capacity = 50,
            .chunk_size = @sizeOf(WindowState),
        },
    });

    try win.init("Odyssey", 0);
    errdefer win.deinit();

    try self.core.init(gpa, io, .{});
    errdefer self.core.deinit();

    try self.renderer.init();
    errdefer self.renderer.deinit();

    try self.display.init(&self.core, displayCallback);
    errdefer self.display.deinit();

    win.setEventCallback(.window_resized, resizeCallback);
}

pub fn deinit(self: *App) void {
    self.renderer.deinit();
    self.core.deinit();
    win.deinit();
    self.arena.deinit();
}

pub fn run(self: *App) void {
    self.core.run(.until_done);
}

pub const WindowState = struct {
    next: ?*WindowState = null,

    win: Window,
    render_handle: Handle,
    view_state: ViewState,

    pub fn init(self: *WindowState, app: *App, opts: win.Options) !void {
        self.* = .{
            .view_state = undefined,
            .win = undefined,
            .render_handle = undefined,
        };

        try self.view_state.init(app.gpa);
        errdefer self.view_state.deinit();

        try self.win.init(opts);
        errdefer self.win.deinit();

        self.win.setUserdata(app);

        try self.render_handle.init(
            &app.renderer,
            &self.win,
            app.gpa,
            app.io,
        );
    }

    pub fn deinit(self: *WindowState) void {
        self.render_handle.deinit();
        self.win.deinit();
        self.view_state.deinit();
    }
};

fn resizeCallback(event: win.Event) void {
    const window = event.win;
    const self: *App = @ptrCast(@alignCast(window.userdata()));

    var curr: ?*WindowState = self.states.head;
    var resized: ?*WindowState = null;

    while (curr) |state| : (curr = state.next) {
        if (state.win.raw == window.raw) {
            resized = state;
        } else {
            self.renderFrame(state, false) catch |err| {
                log.err("Frame render err={}", .{err});
            };
        }
    }

    if (resized) |state| {
        self.renderFrame(state, true) catch |err| {
            log.err("Frame render err={}", .{err});
        };
    }
}

fn displayCallback(display: *Display) bool {
    const self: *App = @fieldParentPtr("display", display);

    self.renderer.start();
    defer self.renderer.end();

    if (self.states.is_empty()) self.core.stop();

    win.pollEvents();

    var states = self.states;
    self.states = .empty;

    const chunks = self.chunks.allocator();

    while (states.pop()) |state| {
        if (state.win.shouldClose()) {
            state.deinit();

            chunks.destroy(state);
        } else {
            self.renderFrame(state, false) catch |err| {
                log.debug("Frame render err={}", .{err});
            };

            self.states.append(state);
        }
    }

    return true;
}

pub fn openWindow(self: *App, opts: win.Options) !void {
    const chunks = self.chunks.allocator();
    const window_state = try chunks.create(WindowState);
    try window_state.init(self, opts);

    self.states.append(window_state);
}

pub fn renderFrame(app: *App, window_state: *WindowState, sync: bool) !void {
    const size = try window_state.win.size();
    {
        const view_state = &window_state.view_state;

        try view_state.begin(.{
            .width = size.w,
            .height = size.h,
        });
        defer view_state.finish();

        try view_state.pushAttrs(&.{ .{ .width = .grow }, .{ .height = .grow } });
        defer view_state.popAttrs(&.{ .width, .height });

        try view_state.nextAttrs(&.{
            .{ .width = .{ .fixed = 100 } },
            .{ .color = .{ 1.0, 0.0, 0.0, 1.0 } },
        });
        _ = try view_state.block(.{}, null);

        try view_state.nextAttrs(&.{
            .{ .color = .{ 0.0, 1.0, 0.0, 1.0 } },
            .{ .height_shrink = 0.0 },
            .{ .width_shrink = 0.0 },
        });
        _ = try view_state.block(.{}, null);

        try view_state.nextAttrs(&.{
            .{ .width = .{ .fixed = 100 } },
            .{ .color = .{ 0.0, 0.0, 1.0, 1.0 } },
        });
        _ = try view_state.block(.{}, null);
    }

    const frame = window_state.render_handle.nextFrame();
    errdefer window_state.render_handle.releaseFrame();

    try frame.uniform(.{
        .viewport_size = .{ size.w, size.h },
    });

    var box = window_state.view_state.root;
    while (box) |current| : (box = current.nextPreOrder()) {
        try frame.rect(.{
            .position = .{
                current.abs_position[0],
                current.abs_position[1],
                current.abs_position[0] + current.size[0],
                current.abs_position[1] + current.size[1],
            },
            .color_0 = current.color,
            .color_1 = current.color,
            .color_2 = current.color,
            .color_3 = current.color,
        });
    }

    render.renderFrame(&app.renderer, &window_state.render_handle, frame, sync);
}
