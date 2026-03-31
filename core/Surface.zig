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
const std = @import("std");
const objc = @import("objc");
const Allocator = std.mem.Allocator;
const Renderer = @import("Renderer.zig");
const RendererThread = @import("renderer/Thread.zig");
const fontpkg = @import("font/mod.zig");
const Grid = fontpkg.Grid;
const SharedState = @import("SharedState.zig");
const Project = @import("Project.zig");
const sizepkg = @import("size.zig");

const log = std.log.scoped(.surface);

const Surface = @This();

alloc: Allocator,

grid: *Grid,

renderer: Renderer,
renderer_thread: RendererThread,
renderer_thr: std.Thread,

shared_state: SharedState,

pub fn create(alloc: Allocator, grid: *Grid, layer_ptr: *anyopaque) !*Surface {
    const metal_layer = objc.Object.fromId(layer_ptr);

    const self = try alloc.create(Surface);
    errdefer alloc.destroy(self);

    var renderer = try Renderer.init(
        alloc,
        .{ .grid = grid, .metal_layer = metal_layer, .size = .{
            .screen = .{ .height = 0, .width = 0 },
            .cell = grid.cellSize(),
        } },
    );
    errdefer renderer.deinit();

    var renderer_thread = try RendererThread.init(alloc, &self.renderer, &self.shared_state);
    errdefer renderer_thread.deinit();

    var shared_state = try SharedState.init(alloc, .{ .screen = .{ .height = 0, .width = 0 }, .cell = grid.cellSize() });
    errdefer shared_state.deinit();

    self.* = .{
        .grid = grid,
        .alloc = alloc,
        .shared_state = shared_state,
        .renderer = renderer,
        .renderer_thread = renderer_thread,
        .renderer_thr = undefined,
    };

    self.renderer_thr = try std.Thread.spawn(.{}, RendererThread.threadMain, .{&self.renderer_thread});
    return self;
}

pub fn wakeup(self: *Surface) void {
    self.renderer_thread.wakeup.notify() catch {};
}

pub fn resize(self: *Surface, size: sizepkg.ScreenSize) void {
    _ = self.renderer_thread.mailbox.push(.{ .resize = size }, .instant);
    self.renderer_thread.wakeup.notify() catch {};
}

pub fn setVisibility(self: *Surface, visible: bool) !void {
    _ = self.renderer_thread.mailbox.push(.{ .visible = visible }, .instant);
    self.renderer_thread.wakeup.notify() catch {};
}

pub fn destroy(self: *Surface) void {
    {
        self.renderer_thread.stop.notify() catch |err|
            log.err("error notifying renderer thread to stop, may stall err={}", .{err});
        self.renderer_thr.join();
    }

    self.renderer_thread.deinit();

    self.renderer.deinit();

    self.shared_state.deinit();

    self.alloc.destroy(self);
}
