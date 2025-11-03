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

const Thread = @import("./renderer/Thread.zig");

const log = std.log.scoped(.surface);

alloc: Allocator,

app: *App,

rt_app: *apprt.App,
rt_surface: *apprt.Surface,

size: apprt.SurfaceSize,
font_size: facepkg.DesiredSize,

renderer: Renderer,
renderer_thread: Thread,
renderer_thr: std.Thread,

//NOTE:
//first, i need to add a font grid
//second, i need to get the cell size from the metrics of the grid
//third, i need to calculate the number of rows and cols that my surface can contain in base of the cell widht and height
//four, i need to repeat the prev step every time my surface change his size
//five, i need to create an atlas
//six, i need to create a texuter in base of the atlas
//seven, i need to create a buffer that store all the data needed for render my char
//  position on the surface
//  position on the atlas
//  size
//eight, this should happen for my message

pub fn init(
    self: *Surface,
    alloc: Allocator,
    app: *App,
    rt_app: *apprt.App,
    rt_surface: *apprt.Surface,
) !void {
    const renderer = try Renderer.init(alloc, .{ .size = rt_surface.size, .rt_surface = rt_surface });

    const size = rt_surface.size;

    var renderer_thread = try Thread.init(alloc, rt_surface, &self.renderer);
    errdefer renderer_thread.deinit();

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

    self.* = .{ .renderer = renderer, .alloc = alloc, .font_size = font_size, .app = app, .rt_app = rt_app, .rt_surface = rt_surface, .size = size, .renderer_thread = renderer_thread, .renderer_thr = undefined };

    self.renderer_thr = try std.Thread.spawn(.{}, Thread.Thread.threadMain, .{&self.renderer_thread});
}

pub fn deinit(self: *Surface) void {
    {
        self.renderer_thread.stop.notify() catch |err|
            log.err("error notifying renderer thread to stop, may stall err={}", .{err});
        self.renderer_thr.join();
    }
    self.renderer.deinit();
    log.info("surface closed addr={x}", .{@intFromPtr(self)});
}

pub fn sizeCallback(self: *Surface, size: apprt.SurfaceSize) void {
    if (std.meta.eql(size, self.size)) return;

    self.size = size;
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
