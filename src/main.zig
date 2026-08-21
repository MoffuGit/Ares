const std = @import("std");
const App = @import("app.zig");
const rgfw = @import("rgfw");
const c = rgfw.c;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    var app: App = undefined;
    try app.init(gpa, io, .{});
    defer app.deinit();

    _ = c.RGFW_init("example", 0);
    const window = c.RGFW_createWindow("a window", 0, 0, 800, 600, c.RGFW_windowCenter);

    while (c.RGFW_window_shouldClose(window) == c.RGFW_FALSE) {
        c.RGFW_pollEvents();
    }

    c.RGFW_window_close(window);
    c.RGFW_deinit();
}
