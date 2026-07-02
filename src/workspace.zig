const std = @import("std");
const App = @import("app.zig");
const Context = App.Context;

pub const Workspace = @This();

count: usize,

pub fn init(self: *Workspace, _: Context(Workspace)) !void {
    self.* = .{
        .count = 0,
    };
}
