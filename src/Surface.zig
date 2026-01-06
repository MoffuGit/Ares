const Surface = @This();
const std = @import("std");

const App = @import("App.zig");
const Allocator = std.mem.Allocator;
const Renderer = @import("renderer.zig").Renderer;
const apprt = @import("./apprt/embedded.zig");
const objc = @import("objc");
const fontpkg = @import("font/mod.zig");
const facepkg = fontpkg.facepkg;
const Face = facepkg.Face;
const sizepkg = @import("size.zig");
const Grid = fontpkg.Grid;
const Editor = @import("editor/mod.zig");

const EditorThread = @import("editor/Thread.zig");
const RenderThread = @import("renderer/Thread.zig");

const log = std.log.scoped(.surface);
const SharedState = @import("SharedState.zig");

alloc: Allocator,

app: *App,

rt_app: *apprt.App,
rt_surface: *apprt.Surface,

size: sizepkg.Size,

renderer: Renderer,
renderer_thread: RenderThread,
renderer_thr: std.Thread,

editor: Editor,
editor_thread: EditorThread,
editor_thr: std.Thread,

font_size: facepkg.DesiredSize,
metrics: facepkg.Metrics,

grid: Grid,

shared_state: SharedState,

pub fn init(
    self: *Surface,
    alloc: Allocator,
    app: *App,
    rt_app: *apprt.App,
    rt_surface: *apprt.Surface,
) !void {
    var renderer_thread = try RenderThread.init(alloc, rt_surface, &self.renderer, &self.shared_state);
    errdefer renderer_thread.deinit();

    var editor_thread = try EditorThread.init(alloc, &self.editor);
    errdefer editor_thread.deinit();

    const content_scale = rt_surface.content_scale;
    const x_dpi = content_scale.x * facepkg.default_dpi;
    const y_dpi = content_scale.y * facepkg.default_dpi;
    log.debug("xscale={} yscale={} xdpi={} ydpi={}", .{
        content_scale.x,
        content_scale.y,
        x_dpi,
        y_dpi,
    });

    const font_size: facepkg.DesiredSize = .{
        .points = 12,
        .xdpi = @intFromFloat(x_dpi),
        .ydpi = @intFromFloat(y_dpi),
    };

    var grid = try Grid.init(alloc, .{ .size = font_size });

    const size: sizepkg.Size = size: {
        const size: sizepkg.Size = .{
            .screen = screen: {
                const surface_size = rt_surface.getSize();
                break :screen .{
                    .width = surface_size.width,
                    .height = surface_size.height,
                };
            },

            .cell = grid.cellSize(),
        };
        break :size size;
    };

    const mutex: std.Thread.Mutex = .{};

    var renderer = try Renderer.init(alloc, .{ .size = size, .rt_surface = rt_surface, .grid = &self.grid });
    errdefer renderer.deinit();
    var editor = try Editor.init(alloc, .{ .size = size, .mutex = mutex, .thread = &self.renderer_thread });
    errdefer editor.deinit();

    self.* = .{ .renderer = renderer, .metrics = grid.metrics, .grid = grid, .alloc = alloc, .font_size = font_size, .app = app, .rt_app = rt_app, .rt_surface = rt_surface, .size = size, .renderer_thread = renderer_thread, .editor = editor, .editor_thread = editor_thread, .renderer_thr = undefined, .editor_thr = undefined, .shared_state = .{ .editor = &self.editor, .mutex = mutex } };

    self.editor_thr = try std.Thread.spawn(.{}, EditorThread.Thread.threadMain, .{&self.editor_thread});
    self.renderer_thr = try std.Thread.spawn(.{}, RenderThread.Thread.threadMain, .{&self.renderer_thread});
}

pub fn deinit(self: *Surface) void {
    {
        self.renderer_thread.stop.notify() catch |err|
            log.err("error notifying renderer thread to stop, may stall err={}", .{err});
        self.renderer_thr.join();
    }
    {
        self.editor_thread.stop.notify() catch |err|
            log.err("error notifying editor thread to stop, may stall err={}", .{err});
        self.editor_thr.join();
    }
    self.renderer.deinit();
    self.editor.deinit();
    log.info("surface closed addr={x}", .{@intFromPtr(self)});
}

pub fn sizeCallback(self: *Surface, size: apprt.SurfaceSize) void {
    const curr_size = self.size.screen;
    const new_size: sizepkg.ScreenSize = .{
        .width = size.width,
        .height = size.height,
    };

    if (curr_size.height == new_size.height and curr_size.width == new_size.width) return;

    self.size.screen = new_size;

    _ = self.editor_thread.mailbox.push(.{ .size = self.size }, .instant);
    self.editor_thread.wakeup.notify() catch {
        log.err("dam, you cant wakeup the editor thread", .{});
    };
}

pub fn contentScaleCallback(self: *Surface, scale: apprt.ContentScale) void {
    const x_dpi = scale.x * facepkg.default_dpi;
    const y_dpi = scale.y * facepkg.default_dpi;

    // Update our font size which is dependent on the DPI
    const size = size: {
        var size = self.font_size;
        size.xdpi = @intFromFloat(x_dpi);
        size.ydpi = @intFromFloat(y_dpi);
        break :size size;
    };

    // If our DPI didn't actually change, save a lot of work by doing nothing.
    if (size.xdpi == self.font_size.xdpi and size.ydpi == self.font_size.ydpi) {
        return;
    }

    self.setFontSize(size);
}

pub fn setFontSize(self: *Surface, size: facepkg.DesiredSize) void {
    log.debug("set font size size={}", .{size.points});

    // Update our font size so future changes work
    self.font_size = size;

    // // We need to build up a new font stack for this font size.
    // const font_grid_key, const font_grid = try self.app.font_grid_set.ref(
    //     &self.config.font,
    //     self.font_size,
    // );
    // errdefer self.app.font_grid_set.deref(font_grid_key);
    //
    // // Set our cell size
    // try self.setCellSize(.{
    //     .width = font_grid.metrics.cell_width,
    //     .height = font_grid.metrics.cell_height,
    // });
    //
    // // Notify our render thread of the new font stack. The renderer
    // // MUST accept the new font grid and deref the old.
    // _ = self.renderer_thread.mailbox.push(.{
    //     .font_grid = .{
    //         .grid = font_grid,
    //         .set = &self.app.font_grid_set,
    //         .old_key = self.font_grid_key,
    //         .new_key = font_grid_key,
    //     },
    // }, .{ .forever = {} });
    //
    // // Once we've sent the key we can replace our key
    // self.font_grid_key = font_grid_key;
    // self.font_metrics = font_grid.metrics;
    //
    // // Schedule render which also drains our mailbox
    // self.queueRender() catch unreachable;
}
