const std = @import("std");
const Io = std.Io;

const global = @import("global.zig");
const App = @import("app.zig");

pub fn main(init: std.process.Init) !void {
    try global.init();
    defer global.deinit();

    const gpa = init.gpa;
    const io = init.io;

    var app: App = undefined;
    try app.init(gpa, io);
    defer app.deinit();

    app.run();
}
