const Editor = @This();

const std = @import("std");
const sizepkg = @import("../size.zig");
const RendererThread = @import("../renderer/Thread.zig");
const Screen = @import("Screen.zig");
const Allocator = std.mem.Allocator;

mutex: std.Thread.Mutex,
screen: Screen,

renderer_thread: *RendererThread,

const Options = struct { size: sizepkg.Size, mutex: std.Thread.Mutex, thread: *RendererThread };

pub fn init(alloc: Allocator, opts: Options) !Editor {
    const screen = try Screen.init(alloc, opts.size);
    const cells_slice = alloc.alloc(u8, 1) catch {
        return .{ .screen = screen, .mutex = opts.mutex, .renderer_thread = opts.thread };
    };
    defer alloc.free(cells_slice);
    return .{ .screen = screen, .mutex = opts.mutex, .renderer_thread = opts.thread };
}

pub fn deinit(self: *Editor) void {
    self.screen.deinit();
}

pub fn resize(self: *Editor, size: sizepkg.Size) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    self.screen.resize(size);

    self.renderer_thread.wakeup.notify() catch {};
}
