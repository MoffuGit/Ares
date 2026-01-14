const std = @import("std");
const vaxis = @import("vaxis");
const builtin = @import("builtin");
const posix = std.posix;

const RendererThread = @import("renderer/Thread.zig");
const Renderer = @import("renderer/mod.zig");

const WindowThread = @import("window/Thread.zig");
const Window = @import("window/mod.zig");

const log = std.log.scoped(.app);

const Allocator = std.mem.Allocator;

const App = @This();

alloc: Allocator,

tty: vaxis.Tty,
buffer: [256]u8 = undefined,

renderer: Renderer,
renderer_thread: RendererThread,
renderer_thr: std.Thread,

window: Window,
window_thread: WindowThread,
window_thr: std.Thread,

pub fn init(self: *App, alloc: Allocator) !void {
    var renderer = try Renderer.init(alloc, &self.tty, &self.window);
    errdefer renderer.deinit();

    var renderer_thread = try RendererThread.init(alloc, &self.renderer);
    errdefer renderer_thread.deinit();

    var window = try Window.init(alloc, renderer_thread.wakeup);
    errdefer window.deinit();

    var window_thread = try WindowThread.init(alloc, &self.window);
    errdefer window_thread.deinit();

    self.* = .{
        .alloc = alloc,
        .tty = undefined,
        .renderer = renderer,
        .renderer_thread = renderer_thread,
        .renderer_thr = undefined,
        .window = window,
        .window_thread = window_thread,
        .window_thr = undefined,
    };

    var tty = try vaxis.Tty.init(&self.buffer);
    self.tty = tty;

    errdefer tty.deinit();

    self.renderer_thr = try std.Thread.spawn(.{}, RendererThread.threadMain, .{&self.renderer_thread});
    self.window_thr = try std.Thread.spawn(.{}, WindowThread.threadMain, .{&self.window_thread});
}

pub fn deinit(self: *App) void {
    {
        self.renderer_thread.stop.notify() catch |err| {
            log.err("error notifying renderer thread to stop, may stall err={}", .{err});
        };
        self.renderer_thr.join();
    }

    {
        self.window_thread.stop.notify() catch |err| {
            log.err("error notifying renderer thread to stop, may stall err={}", .{err});
        };
        self.window_thr.join();
    }

    self.renderer_thread.deinit();
    self.window_thread.deinit();

    self.window.deinit();
    self.renderer.deinit();
}

pub fn run(self: *App) !void {
    var parser: vaxis.Parser = .{};

    var buf: [1024]u8 = undefined;
    var read_start: usize = 0;

    var cache: vaxis.GraphemeCache = .{};

    const winsize = try vaxis.Tty.getWinsize(self.tty.fd);

    _ = self.window_thread.mailbox.push(.{ .resize = winsize }, .instant);
    try self.window_thread.wakeup.notify();

    while (true) {
        const n = self.tty.read(buf[read_start..]) catch |err| {
            if (err == error.WouldBlock) continue else return err;
        };
        var seq_start: usize = 0;
        while (seq_start < n) {
            const result = try parser.parse(buf[seq_start..n], self.alloc);
            if (result.n == 0) {
                // copy the read to the beginning. We don't use memcpy because
                // this could be overlapping, and it's also rare
                const initial_start = seq_start;
                while (seq_start < n) : (seq_start += 1) {
                    buf[seq_start - initial_start] = buf[seq_start];
                }
                read_start = seq_start - initial_start + 1;
                continue;
            }
            read_start = 0;
            seq_start += result.n;

            const event = result.event orelse continue;
            try self.eventCallback(&cache, event);
        }
    }
}

fn eventCallback(self: *App, cache: *vaxis.GraphemeCache, event: vaxis.Event) !void {
    _ = cache;
    switch (event) {
        .winsize => |size| {
            _ = self.window_thread.mailbox.push(.{ .resize = size }, .instant);
            try self.window_thread.wakeup.notify();
        },
        else => {},
    }
}
