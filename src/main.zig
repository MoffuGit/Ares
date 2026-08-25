const std = @import("std");

const App = @import("app.zig");
const WindowState = App.WindowState;
const datastruct = @import("datastruct.zig");
const SinglyLinkedList = datastruct.SinglyLinkedList;
const global = @import("global.zig");
const Loop = @import("loop.zig");
const Completion = Loop.Completion;
const win = @import("window.zig");

const log = std.log.scoped(.main);

pub fn main(init: std.process.Init) !void {
    try global.state.init();
    defer global.state.deinit();

    const gpa = init.gpa;
    const io = init.io;

    var app: App = undefined;
    try app.init(gpa, io, .{});
    defer app.deinit();

    var context: Context = .{
        .app = &app,
        .tick_h = .noop,
    };

    const chunks = app.chunks.allocator();
    const state = try chunks.create(WindowState);

    try state.init(.{
        .name = "Odyssey",
        .x = 0,
        .y = 0,
        .width = 800,
        .height = 600,
        .flags = win.WindowCenter | win.WindowFocus,
        .userdata = &context,
    }, &app.renderer);
    errdefer state.deinit();

    app.window_states.append(state);

    app.timer(&context.tick_h, tick, 8);
    app.run(.until_done);
}

const Context = struct {
    app: *App,
    tick_h: Completion,
};

pub fn tick(completion: *Completion, loop: *Loop, res: anyerror!void) bool {
    res catch loop.stop();

    const context: *Context = @fieldParentPtr("tick_h", completion);
    const app = context.app;

    _tick(app) catch loop.stop();

    return true;
}

pub fn _tick(app: *App) !void {
    const chunks = app.chunks.allocator();

    if (app.window_states.empty()) app.stop();

    win.pollEvents();

    var states: SinglyLinkedList(WindowState) = .{};

    while (app.window_states.pop()) |state| {
        if (state.win.shouldClose()) {
            state.deinit();

            chunks.destroy(state);
        } else {
            try app.renderer.render(&state.win, &state.handler);
            states.append(state);
        }
    }

    app.window_states = states;
}
