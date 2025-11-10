pub const Renderer = @This();

const Metal = @import("renderer/Metal.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const Options = @import("renderer/Options.zig");
const ArenaAllocator = std.heap.ArenaAllocator;
const objc = @import("objc");
const mtl = @import("./renderer/metal/api.zig");
const SwapChain = @import("./renderer/SwapChain.zig");
const macos = @import("macos");
const Thread = @import("renderer/Thread.zig");
const xev = @import("global.zig").xev;
const sizepkg = @import("size.zig");
const fontpkg = @import("font/mod.zig");
const SharedState = @import("SharedState.zig");
const math = @import("math.zig");
const ArrayList = std.ArrayList;

const log = std.log.scoped(.renderer);

pub const GraphicsAPI = Metal;

const shaderpkg = GraphicsAPI.shaders;
const Shaders = shaderpkg.Shaders;
const Buffer = GraphicsAPI.Buffer;
const Texture = GraphicsAPI.Texture;
const Uniforms = shaderpkg.Uniforms;

//NOTE:
//i need to move some things,
//first, my cells should rebuild not only when the content change,but when the size of the iwndow change
//as well

pub const Health = enum(c_int) {
    healthy = 0,
    unhealthy = 1,
};

alloc: Allocator,

api: Metal,
shaders: Shaders,
uniforms: Uniforms,

mutex: std.Thread.Mutex = .{},

health: std.atomic.Value(Health) = .{ .raw = .healthy },
display_link: ?*macos.video.DisplayLink = null,
swap_chain: SwapChain,

first: bool = true,

size: sizepkg.Size,

grid_size: sizepkg.GridSize = .{},
cells: []shaderpkg.CellText,

grid: *fontpkg.Grid,

rebuild_cells: bool = false,

pub fn init(alloc: Allocator, opts: Options) !Renderer {
    var api = try Metal.init(opts.rt_surface);
    errdefer api.deinit();

    var swap_chain = try SwapChain.init(&api);
    errdefer swap_chain.deinit();

    const display_link = try macos.video.DisplayLink.createWithActiveCGDisplays();
    errdefer display_link.release();

    var renderer = Renderer{ .alloc = alloc, .size = opts.size, .api = api, .shaders = undefined, .swap_chain = swap_chain, .display_link = display_link, .grid = opts.grid, .uniforms = .{ .grid_size = undefined, .cell_size = undefined, .screen_size = undefined, .projection_matrix = undefined }, .cells = &.{} };

    try renderer.initShaders();
    renderer.updateFontGridUniforms();
    renderer.updateScreenSizeUniforms();

    return renderer;
}

fn updateFontGridUniforms(self: *Renderer) void {
    self.uniforms.cell_size = .{
        @floatFromInt(self.size.cell.width),
        @floatFromInt(self.size.cell.height),
    };
}

fn updateScreenSizeUniforms(self: *Renderer) void {
    self.uniforms.projection_matrix = math.ortho2d(
        0,
        @floatFromInt(self.size.screen.width),
        @floatFromInt(self.size.screen.height),
        0,
    );
    self.uniforms.screen_size = .{
        @floatFromInt(self.size.screen.width),
        @floatFromInt(self.size.screen.height),
    };
}

pub fn deinit(self: *Renderer) void {
    self.api.deinit();
    self.swap_chain.deinit();
    if (self.display_link) |link| {
        link.stop() catch {};
        link.release();
    }
    self.deinitShaders();
    self.alloc.free(self.cells);
    self.* = undefined;
}

fn deinitShaders(self: *Renderer) void {
    self.shaders.deinit();
}

fn initShaders(self: *Renderer) !void {
    var shaders = try self.api.initShaders();
    errdefer shaders.deinit(self.alloc);

    self.shaders = shaders;
}

pub fn drawFrame(
    self: *Renderer,
    sync: bool,
) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    self.api.drawFrameStart();
    defer self.api.drawFrameEnd();

    const surface_size = try self.api.surfaceSize();

    if (surface_size.width == 0 or surface_size.height == 0) return;

    const size_changed =
        self.size.screen.width != surface_size.width or
        self.size.screen.height != surface_size.height;

    const needs_redraw =
        size_changed or sync or self.rebuild_cells;

    if (!needs_redraw) return;

    const frame = try self.swap_chain.nextFrame();
    errdefer self.swap_chain.releaseFrame();

    if (size_changed) {
        self.size.screen = .{
            .width = surface_size.width,
            .height = surface_size.height,
        };
        self.updateScreenSizeUniforms();
    }

    if (frame.target.width != self.size.screen.width or
        frame.target.height != self.size.screen.height)
    {
        try frame.resize(
            &self.api,
            self.size.screen.width,
            self.size.screen.height,
        );
    }

    try frame.uniforms.sync(&.{self.uniforms});

    try frame.cells.sync(self.cells);

    self.rebuild_cells = false;

    try self.syncAtlasTexture(&self.grid.atlas_grayscale, &frame.grayscale);

    var frame_ctx = try self.api.beginFrame(self, &frame.target);
    defer frame_ctx.complete(sync);

    {
        var render_pass = frame_ctx.renderPass(&.{
            .{
                .target = .{
                    .target = frame.target,
                },
                .clear_color = .{ 0.0, 0.0, 0.0, 0.0 },
            },
        });
        // render_pass.step(.{
        //     .pipeline = self.shaders.pipelines.grid, // Assuming 'grid' pipeline is created
        //     .uniforms = frame.uniforms.buffer,
        //     .buffers = &.{frame.vertex.buffer}, // Use the same full-screen quad for the grid
        //     .draw = .{ .vertex_count = 4, .type = .triangle_strip },
        // });
        render_pass.step(.{
            .pipeline = self.shaders.pipelines.cell,
            .uniforms = frame.uniforms.buffer,
            .buffers = &.{
                frame.cells.buffer,
            },
            .textures = &.{
                frame.grayscale,
            },
            .draw = .{
                .type = .triangle_strip,
                .vertex_count = 4,
                .instance_count = self.cells.len,
            },
        });
        //

        defer render_pass.complete();
    }
}

pub fn frameCompleted(
    self: *Renderer,
    health: Health,
) void {
    // If our health value hasn't changed, then we do nothing. We don't
    // do a cmpxchg here because strict atomicity isn't important.
    if (self.health.load(.seq_cst) != health) {
        self.health.store(health, .seq_cst);

        // Our health value changed, so we notify the surface so that it
        // can do something about it.
        // _ = self.surface_mailbox.push(.{
        //     .renderer_health = health,
        // }, .{ .forever = {} });
    }

    // Always release our semaphore
    self.swap_chain.releaseFrame();
}

pub fn hasVsync(self: *const Renderer) bool {
    const display_link = self.display_link orelse return false;
    return display_link.isRunning();
}

pub fn loopEnter(self: *Renderer, thr: *Thread) !void {
    self.api.loopEnter();
    // This is when we know our "self" pointer is stable so we can
    // setup the display link. To setup the display link we set our
    // callback and we can start it immediately.
    const display_link = self.display_link orelse return;
    try display_link.setOutputCallback(
        xev.Async,
        &displayLinkCallback,
        &thr.draw_now,
    );
    display_link.start() catch {};
}

pub fn loopExit(self: *Renderer) void {
    // Stop our display link. If this fails its okay it just means
    // that we either never started it or the view its attached to
    // is gone which is fine.
    const display_link = self.display_link orelse return;
    display_link.stop() catch {};
}

fn displayLinkCallback(
    _: *macos.video.DisplayLink,
    ud: ?*xev.Async,
) void {
    const draw_now = ud orelse return;
    draw_now.notify() catch |err| {
        log.err("error notifying draw_now err={}", .{err});
    };
}

pub fn updateFrame(self: *Renderer, state: *SharedState) !void {
    const Critical = struct { row: u16, col: u16, cells: ArrayList([]u32) };
    var critical: Critical = critical: {
        state.mutex.lock();
        defer state.mutex.unlock();

        const screen = state.editor.screen;

        var new_cells = try ArrayList([]u32).initCapacity(self.alloc, screen.cells.items.len);
        errdefer {
            for (new_cells.items) |slice| {
                self.alloc.free(slice);
            }
            new_cells.deinit(self.alloc);
        }

        for (screen.cells.items) |row_slice| {
            const allocated_row = try self.alloc.alloc(u32, row_slice.len);
            @memcpy(allocated_row, row_slice);
            try new_cells.append(self.alloc, allocated_row);
        }

        break :critical .{ .col = screen.cols, .row = screen.rows, .cells = new_cells };
    };

    defer {
        for (critical.cells.items) |slice| {
            self.alloc.free(slice);
        }
        critical.cells.deinit(self.alloc);
    }

    self.rebuildCells(critical.row, critical.col, critical.cells) catch {};
}

fn rebuildCells(self: *Renderer, row: u16, col: u16, new_cells: ArrayList([]u32)) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    const grid_size_diff =
        self.grid_size.rows != row or
        self.grid_size.columns != col;

    if (grid_size_diff) {
        var new_size = self.grid_size;
        new_size.rows = row;
        new_size.columns = col;
        self.grid_size = new_size;
        self.uniforms.grid_size = .{ new_size.columns, new_size.rows };
    }

    self.rebuild_cells = true;

    var total_cells: usize = 0;
    for (new_cells.items) |row_cells| {
        total_cells += row_cells.len;
    }

    var glyphs = try self.alloc.alloc(shaderpkg.CellText, total_cells);

    var glyphs_idx: usize = 0;
    for (new_cells.items, 0..) |row_cells, row_idx| {
        if (row_idx >= self.grid_size.rows) break;

        for (row_cells, 0..) |cell_codepoint, col_idx| {
            if (col_idx >= self.grid_size.columns) break;

            const glyph = self.grid.renderCodepoint(self.alloc, cell_codepoint) catch {
                continue;
            };

            glyphs[glyphs_idx] = shaderpkg.CellText{
                .grid_pos = .{ @intCast(col_idx), @intCast(row_idx) },
                .color = .{ 1.0, 0.0, 0.0, 1.0 },
                .glyph_pos = .{ glyph.atlas_x, glyph.atlas_y },
                .glyph_size = .{ glyph.width, glyph.height },
                .bearings = .{
                    @intCast(glyph.offset_x),
                    @intCast(glyph.offset_y),
                },
            };
            glyphs_idx += 1;
        }
    }

    self.alloc.free(self.cells);
    self.cells = glyphs;
}

fn syncAtlasTexture(
    self: *const Renderer,
    atlas: *const fontpkg.Atlas,
    texture: *Texture,
) !void {
    if (atlas.size > texture.width) {
        // Free our old texture
        texture.*.deinit();

        // Reallocate
        texture.* = try self.api.initAtlasTexture(atlas);
    }

    try texture.replaceRegion(0, 0, atlas.size, atlas.size, atlas.data);
}
