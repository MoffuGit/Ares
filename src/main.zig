const std = @import("std");
const Io = std.Io;

const App = @import("app.zig");
const WindowState = App.WindowState;
const datastruct = @import("datastruct.zig");
const SinglyLinkedList = datastruct.SinglyLinkedList;
const global = @import("global.zig");
const Loop = @import("loop.zig");
const Completion = Loop.Completion;
const win = @import("window.zig");
const Window = win.Window;

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

    win.setEventCallback(win.WindowResized, windowCallback);

    const chunks = app.chunks.allocator();
    const window_state = try chunks.create(WindowState);

    try window_state.init(.{
        .name = "Odyssey",
        .x = 0,
        .y = 0,
        .width = 800,
        .height = 600,
        .flags = win.WindowCenter | win.WindowFocus,
        .userdata = &context,
    }, &app.renderer);
    errdefer window_state.deinit();

    app.states.append(window_state);

    app.timer(&context.tick_h, tick, 16);
    app.run(.until_done);
}

const Context = struct {
    app: *App,
    tick_h: Completion,
};

pub fn tick(completion: *Completion, loop: *Loop, res: anyerror!void) bool {
    res catch loop.stop();

    const context: *Context = @alignCast(@fieldParentPtr("tick_h", completion));
    const app = context.app;

    _tick(app) catch loop.stop();

    return true;
}

pub fn _tick(app: *App) !void {
    const chunks = app.chunks.allocator();

    if (app.states.empty()) app.stop();

    win.pollEvents();

    var states: SinglyLinkedList(WindowState) = .{};

    while (app.states.pop()) |state| {
        if (state.win.shouldClose()) {
            state.deinit();

            chunks.destroy(state);
        } else {
            try app.renderer.render(&state.win, &state.handler);
            states.append(state);
        }
    }

    app.states = states;
}

pub fn windowCallback(event: [*c]const win.Event) callconv(.c) void {
    const window: Window = .{ .raw = event.*.common.win };
    const context: *Context = @ptrCast(@alignCast(window.userdata()));
    const app = context.app;

    var curr: ?*WindowState = app.states.head;

    while (curr) |state| : (curr = state.next) {
        if (state.win.raw == window.raw) {
            app.renderer.render(&state.win, &state.handler) catch {};
            break;
        }
    }
}
