const std = @import("std");
const App = @import("app.zig");
const rgfw = @import("rgfw");
const Window = rgfw.Window;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    var app: App = undefined;
    try app.init(gpa, io, .{});
    defer app.deinit();

    app.setTimer();
    app.run(.until_done);
}
