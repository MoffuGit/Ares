const Terminal = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const ghostty_vt = @import("ghostty-vt");
const Thread = @import("terminal/Thread.zig");
const sizepkg = @import("size.zig");

const log = std.log.scoped(.terminal);

alloc: Allocator,
ptr: *anyopaque,

thread: Thread,
thr: std.Thread,

term: ghostty_vt.Terminal,

pub fn create(alloc: Allocator, layer_ptr: *anyopaque) !*Terminal {
    const self = try alloc.create(Terminal);
    errdefer alloc.destroy(self);

    var thread = try Thread.init(alloc, self);
    errdefer thread.deinit();

    var term = try ghostty_vt.Terminal.init(alloc, .{
        .cols = 0,
        .rows = 0,
        .max_scrollback = 1000,
    });
    errdefer term.deinit(alloc);

    self.* = .{
        .term = term,
        .alloc = alloc,
        .ptr = layer_ptr,
        .thread = thread,
        .thr = undefined,
    };

    self.thr = try std.Thread.spawn(.{}, Thread.threadMain, .{&self.thread});

    return self;
}

pub fn resize(self: *Terminal, size: sizepkg.ScreenSize) void {
    _ = self;
    _ = size;
}

pub fn destroy(self: *Terminal) void {
    {
        self.thread.stop.notify() catch {};
        self.thr.join();
    }

    self.term.deinit(self.alloc);

    self.thread.deinit();

    self.alloc.destroy(self);
}
