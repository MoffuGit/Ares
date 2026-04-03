const Terminal = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const ghostty_vt = @import("ghostty-vt");
const Thread = @import("terminal/Thread.zig");
const Surface = @import("Surface.zig");
const sizepkg = @import("size.zig");
const App = @import("App.zig");

const log = std.log.scoped(.terminal);

alloc: Allocator,
surface: *Surface,

thread: Thread,
thr: std.Thread,

// term: ghostty_vt.Terminal,

pub fn create(app: *App, alloc: Allocator, layer_ptr: *anyopaque) !*Terminal {
    const self = try alloc.create(Terminal);
    errdefer alloc.destroy(self);

    const surface = try Surface.create(alloc, &app.grid, layer_ptr);
    errdefer surface.destroy();

    var thread = try Thread.init(alloc, self);
    errdefer thread.deinit();

    // var term = try ghostty_vt.Terminal.init(alloc, .{
    //     .cols = 0,
    //     .rows = 0,
    //     .max_scrollback = 1000,
    // });
    // errdefer term.deinit(alloc);

    self.* = .{
        // .term = term,
        .alloc = alloc,
        .surface = surface,
        .thread = thread,
        .thr = undefined,
    };

    self.thr = try std.Thread.spawn(.{}, Thread.threadMain, .{&self.thread});

    return self;
}

pub fn resize(self: *Terminal, size: sizepkg.ScreenSize) void {
    _ = self.surface.renderer_thread.mailbox.push(.{ .resize = size }, .instant);
    self.surface.renderer_thread.wakeup.notify() catch {};
}

pub fn destroy(self: *Terminal) void {
    {
        self.thread.stop.notify() catch {};
        self.thr.join();
    }

    self.surface.destroy();

    // self.term.deinit(self.alloc);

    self.thread.deinit();

    self.alloc.destroy(self);
}
