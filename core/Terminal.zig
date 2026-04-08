const std = @import("std");
const ghostty_vt = @import("ghostty-vt");

const Allocator = std.mem.Allocator;

const Terminal = @This();

alloc: Allocator,
term: ghostty_vt.Terminal,

pub fn init(alloc: Allocator, opts: ghostty_vt.Terminal.Options) !Terminal {
    return .{ .alloc = alloc, .term = try ghostty_vt.Terminal.init(alloc, opts) };
}

pub fn deinit(self: *Terminal) void {
    self.term.deinit(self.alloc);
}
