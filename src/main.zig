const std = @import("std");
const Io = std.Io;

const macos = @import("macos");

const App = @import("app.zig");
const WindowState = App.WindowState;
const datastruct = @import("datastruct.zig");
const SinglyLinkedList = datastruct.SinglyLinkedList;
const global = @import("global.zig");
const Loop = @import("loop.zig");
const Completion = Loop.Completion;
const Waker = Loop.Waker;
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
        .display_c = .noop,
        .waker = undefined,
    };

    context.waker = try app.await(&context.display_c, tick);

    win.setEventCallback(win.WindowResized, windowCallback);

    const chunks = app.chunks.allocator();
    const window_state = try chunks.create(WindowState);

    try window_state.init(
        &app,
        .{
            .name = "Odyssey",
            .x = 0,
            .y = 0,
            .width = 800,
            .height = 600,
            .flags = win.WindowCenter | win.WindowFocus,
            .userdata = &context,
        },
    );

    errdefer window_state.deinit();

    app.states.append(window_state);

    const result = try macos.video.DisplayLink.createWithActiveCGDisplays();
    result.setOutputCallback(
        Waker,
        &displayLinkCallback,
        &context.waker,
    ) catch |err| {
        log.warn("error configuring display link err={}", .{err});
        result.release();
        return;
    };

    try result.start();

    app.run(.until_done);
}

fn displayLinkCallback(
    _: *macos.video.DisplayLink,
    ud: ?*Waker,
) void {
    if (ud) |waker| {
        waker.wake() catch {};
    }
}

const Context = struct {
    app: *App,
    display_c: Completion,
    waker: Waker,
};

pub fn tick(completion: *Completion, loop: *Loop, res: anyerror!void) bool {
    res catch loop.stop();

    const context: *Context = @alignCast(@fieldParentPtr("display_c", completion));
    const app = context.app;

    _tick(app) catch loop.stop();

    return true;
}

pub fn _tick(app: *App) !void {
    const chunks = app.chunks.allocator();

    if (app.states.is_empty()) app.stop();

    win.pollEvents();

    var states: SinglyLinkedList(WindowState) = .empty;

    while (app.states.pop()) |state| {
        if (state.win.shouldClose()) {
            state.deinit();

            chunks.destroy(state);
        } else {
            const width, const height = state.win.sizeInPixels() orelse unreachable;
            const frame = state.handle.nextFrame();

            try frame.uniform(.{
                .viewport_size = .{ @floatFromInt(width), @floatFromInt(height) },
            });

            try frame.rect(.{
                .position = .{ 10.0, 10.0, 110.0, 110.0 },
                .color_0 = .{ 1.0, 0.0, 0.0, 1.0 },
                .color_1 = .{ 1.0, 0.0, 0.0, 1.0 },
                .color_2 = .{ 1.0, 0.0, 0.0, 1.0 },
                .color_3 = .{ 1.0, 0.0, 0.0, 1.0 },
            });

            app.renderer.render(&state.handle, frame, false);

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
            const width, const height = state.win.sizeInPixels() orelse unreachable;
            const frame = state.handle.nextFrame();

            frame.uniform(.{
                .viewport_size = .{ @floatFromInt(width), @floatFromInt(height) },
            }) catch unreachable;

            frame.rect(.{
                .position = .{ 10, 10, 110, 110 },
                .color_0 = .{ 1, 0, 0, 1 },
                .color_1 = .{ 1, 0, 0, 1 },
                .color_2 = .{ 1, 0, 0, 1 },
                .color_3 = .{ 1, 0, 0, 1 },
            }) catch unreachable;

            app.renderer.render(&state.handle, frame, true);
            break;
        }
    }
}
