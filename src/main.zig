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

    try rgfw.init("example", 0);
    defer rgfw.deinit();

    var window: rgfw.Window = undefined;
    try window.init("a window", 0, 0, 800, 600, Window.WindowCenter | Window.WindowNoResize);
    defer window.deinit();

    while (!window.shouldClose()) {
        rgfw.pollEvents();
    }
}
