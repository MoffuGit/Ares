const std = @import("std");
const App = @import("app.zig");
const Context = App.Context;
const sch = @import("scheduler.zig");
const Waker = sch.Waker;
const BackgroundScheduler = sch.BackgroundScheduler;

pub const Workspace = @This();

pub fn init(self: *Workspace, _: Context(Workspace)) !void {
    self.* = .{};
}
