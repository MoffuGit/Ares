const std = @import("std");
const App = @import("app.zig");
const rgfw = @import("rgfw");
const Window = rgfw.Window;
const state = &@import("global.zig").state;

pub fn main(init: std.process.Init) !void {
    try state.init();
    defer state.deinit();

    const gpa = init.gpa;
    const io = init.io;

    var app: App = undefined;
    try app.init(gpa, io, .{});
    defer app.deinit();

    app.setTickTimer();
    app.run(.until_done);
}
