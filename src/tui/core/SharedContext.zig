const SharedContext = @This();

const vaxis = @import("vaxis");

const Allocator = std.mem.Allocator;

var TTY_BUFFER: [1024]u8 = undefined;

const std = @import("std");

mutex: std.Thread.Mutex = .{},

tty: vaxis.Tty,
vx: vaxis.Vaxis,

pub fn init(alloc: Allocator) !SharedContext {
    const tty = try vaxis.Tty.init(&TTY_BUFFER);
    errdefer tty.deinit();

    const vx = try vaxis.init(alloc, .{});
    errdefer vx.deinit(alloc, tty.writer());

    return .{
        .tty = tty,
        .vx = vx,
    };
}

pub fn deinit(self: *SharedContext, alloc: Allocator) void {
    self.vx.deinit(alloc, self.tty.writer());
    self.tty.deinit();
}
