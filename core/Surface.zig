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

const std = @import("std");
const objc = @import("objc");
const Allocator = std.mem.Allocator;
const globalpkg = @import("global.zig");
const Renderer = @import("Renderer.zig");
const RendererThread = @import("renderer/Thread.zig");
const fontpkg = @import("font/mod.zig");
const Grid = fontpkg.Grid;
const sizepkg = @import("size.zig");
const Settings = @import("settings/mod.zig");

const log = std.log.scoped(.surface);

pub fn Surface(comptime Io: type, comptime State: type) type {
    return struct {
        const Self = @This();

        alloc: Allocator,
        grid: *Grid,

        renderer: Renderer,
        renderer_thread: RendererThread,
        renderer_thr: std.Thread,

        io: Io,
        io_thread: Io.Thread,
        io_thr: std.Thread,

        state: State,

        pub fn create(
            alloc: Allocator,
            grid: *Grid,
            layer_ptr: *anyopaque,
            screen_size: sizepkg.ScreenSize,
            state: State,
            settings: *Settings,
        ) !*Self {
            const metal_layer = objc.Object.fromId(layer_ptr);

            const self = try alloc.create(Self);
            errdefer alloc.destroy(self);

            var renderer = try Renderer.init(
                alloc,
                settings,
                .{ .grid = grid, .metal_layer = metal_layer, .size = .{
                    .screen = screen_size,
                    .cell = grid.cellSize(),
                } },
            );
            errdefer renderer.deinit();

            var renderer_thread = try RendererThread.init(alloc, &self.renderer);
            errdefer renderer_thread.deinit();

            var io = try Io.init(
                alloc,
                grid,
                &self.renderer,
                &self.renderer_thread,
                screen_size,
                &self.state,
            );
            errdefer io.deinit();

            var io_thread = try Io.Thread.init(alloc, &self.io);
            errdefer io_thread.deinit();

            self.* = .{
                .alloc = alloc,
                .grid = grid,
                .renderer = renderer,
                .renderer_thread = renderer_thread,
                .renderer_thr = undefined,
                .io = io,
                .io_thread = io_thread,
                .io_thr = undefined,
                .state = state,
            };

            self.renderer_thr = try std.Thread.spawn(.{}, RendererThread.threadMain, .{&self.renderer_thread});
            errdefer {
                self.renderer_thread.stop.notify() catch {};
                self.renderer_thr.join();
            }

            self.io_thr = try std.Thread.spawn(.{}, Io.Thread.threadMain, .{&self.io_thread});
            errdefer {
                self.io_thread.stop.notify() catch {};
                self.io_thr.join();
            }

            self.emitStateUpdate();

            return self;
        }

        pub fn wakeup(self: *Self) void {
            self.renderer_thread.wakeup.notify() catch {};
        }

        pub fn surfaceState(self: *Self, out: *globalpkg.ExternSurfaceState) void {
            out.* = .{
                .cell_width = self.renderer.size.cell.width,
                .cell_height = self.renderer.size.cell.height,
                .renderer_health = @intCast(@intFromEnum(self.renderer.health.load(.seq_cst))),
            };
        }

        fn emitStateUpdate(self: *Self) void {
            var surface_state: globalpkg.ExternSurfaceState = undefined;
            self.surfaceState(&surface_state);
            _ = globalpkg.state.emit(.{ .surfaceUpdate = surface_state }, .instant);
        }

        pub fn sendIo(self: *Self, message: Io.Thread.Message) void {
            _ = self.io_thread.mailbox.push(message, .instant);
            self.io_thread.wakeup.notify() catch {};
        }

        pub fn setVisibility(self: *Self, visible: bool) !void {
            _ = self.renderer_thread.mailbox.push(.{ .visible = visible }, .instant);
            self.renderer_thread.wakeup.notify() catch {};
        }

        pub fn destroy(self: *Self) void {
            {
                self.io_thread.stop.notify() catch |err|
                    log.err("error notifying io thread to stop, may stall err={}", .{err});
                self.io_thr.join();
            }

            {
                self.renderer_thread.stop.notify() catch |err|
                    log.err("error notifying renderer thread to stop, may stall err={}", .{err});
                self.renderer_thr.join();
            }

            self.io_thread.deinit();
            self.io.deinit();

            self.renderer_thread.deinit();
            self.renderer.deinit();

            self.state.deinit();

            self.alloc.destroy(self);
        }
    };
}
