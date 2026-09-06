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

    // const chunks = app.chunks.allocator();
    // const window_state = try chunks.create(App.WindowState);
    //
    // try window_state.init(
    //     &app.renderer,
    //     .{
    //         .name = "Odyssey",
    //         .x = 0,
    //         .y = 0,
    //         .width = 800,
    //         .height = 600,
    //         .flags = win.WindowCenter | win.WindowFocus,
    //         .userdata = &context,
    //     },
    //     app.gpa,
    //     app.io,
    // );
    //
    // errdefer window_state.deinit();
    //
    // app.states.append(window_state);
    //
    app.run();
}
