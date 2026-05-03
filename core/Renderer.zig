// MIT License
//
// Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//
//all the files inside the renderer dir share this license
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
const globalpkg = @import("global.zig");
const global = &globalpkg.state;
const xev = globalpkg.xev;
const sizepkg = @import("size.zig");
const fontpkg = @import("font/mod.zig");
const math = @import("math.zig");
const Settings = @import("settings/mod.zig");
pub const GridSize = sizepkg.GridSize;
const Contents = @import("renderer/Content.zig").Contents;

const log = std.log.scoped(.renderer);

pub const GraphicsAPI = Metal;

const shaderpkg = GraphicsAPI.shaders;
const Shaders = shaderpkg.Shaders;
const Buffer = GraphicsAPI.Buffer;
const Texture = GraphicsAPI.Texture;
const Uniforms = shaderpkg.Uniforms;

pub const Health = enum(c_int) {
    healthy = 0,
    unhealthy = 1,
};

pub const FrameCallback = *const fn (*anyopaque, *Renderer) void;

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
surface_id: u64,

grid_size: GridSize = .{},
cells: Contents = .{},

grid: *fontpkg.Grid,

cells_rebuilt: bool = true,

settings: *Settings,

state: *anyopaque,
update_frame: FrameCallback,

pub fn init(alloc: Allocator, settings: *Settings, opts: Options) !Renderer {
    var api = try Metal.init(opts.metal_layer);
    errdefer api.deinit();

    var swap_chain = try SwapChain.init(&api);
    errdefer swap_chain.deinit();

    const display_link = try macos.video.DisplayLink.createWithActiveCGDisplays();
    errdefer display_link.release();

    var renderer = Renderer{
        .state = opts.state,
        .update_frame = opts.frame_callback,
        .alloc = alloc,
        .size = opts.size,
        .surface_id = opts.surface_id,
        .api = api,
        .shaders = undefined,
        .swap_chain = swap_chain,
        .display_link = display_link,
        .grid = opts.grid,
        .settings = settings,
        .uniforms = .{
            .grid_size = .{ 0, 0 },
            .cell_size = undefined,
            .screen_size = undefined,
            .projection_matrix = undefined,
            .cursor_pos = .{ 0, 0 },
            .cursor_color = .{ 0, 0, 0, 0 },
            .bg_color = settings.getColor(.mutedBg),
        },
    };

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

pub fn setScreenSize(self: *Renderer, _: sizepkg.ScreenSize) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    self.updateScreenSizeUniforms();
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
    self.cells.deinit(self.alloc);
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
        size_changed or sync or self.cells_rebuilt;

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

    const fg_count = try frame.cells.syncFromArrayLists(self.cells.fg_rows.lists);

    self.cells_rebuilt = false;

    {
        self.grid.lock.lockShared();
        defer self.grid.lock.unlockShared();
        try self.syncAtlasTexture(&self.grid.atlas_grayscale, &frame.grayscale);
    }

    var frame_ctx = try self.api.beginFrame(self, &frame.target);
    defer frame_ctx.complete(sync);

    {
        var pass = frame_ctx.renderPass(&.{
            .{
                .target = .{
                    .target = frame.target,
                },
                .clear_color = .{ 0.0, 0.0, 0.0, 0.0 },
            },
        });
        pass.step(.{
            .pipeline = self.shaders.pipelines.bg_color,
            .uniforms = frame.uniforms.buffer,
            .buffers = &.{ null, frame.cells_bg.buffer },
            .draw = .{ .type = .triangle, .vertex_count = 3 },
        });

        pass.step(.{
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
                .instance_count = fg_count,
            },
        });
        //

        defer pass.complete();
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
        self.emitSurfaceUpdate();
    }

    // Always release our semaphore
    self.swap_chain.releaseFrame();
}

fn emitSurfaceUpdate(self: *Renderer) void {
    _ = global.emit(.{ .surfaceUpdate = .{
        .surface_id = self.surface_id,
        .cell_width = self.size.cell.width,
        .cell_height = self.size.cell.height,
        .renderer_health = @intCast(@intFromEnum(self.health.load(.seq_cst))),
    } }, .instant);
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

pub fn loopExit(self: *Renderer, _: *Thread) void {
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

pub fn updateFrame(self: *Renderer) !void {
    self.update_frame(self.state, self);
}

pub fn ensureCellStoreSize(self: *Renderer, size: GridSize) !void {
    if (self.grid_size.equals(size)) return;

    self.grid_size = size;
    self.uniforms.grid_size = .{ size.columns, size.rows };
    try self.cells.resize(self.alloc, size);
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

pub fn setVisible(self: *Renderer, visible: bool) void {
    const display_link = self.display_link orelse return;
    if (visible) {
        display_link.start() catch {};
    } else {
        display_link.stop() catch {};
    }
}
