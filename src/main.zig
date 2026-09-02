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
const renderer = @import("renderer.zig");
const win = @import("window.zig");
const Window = win.Window;

const log = std.log.scoped(.main);

const Context = struct {
    app: *App,
    display_c: Completion,
    waker: Waker,
};

pub fn main(init: std.process.Init) !void {
    try global.state.init();
    defer global.state.deinit();

    win.setEventCallback(win.WindowResized, struct {
        fn callback(event: [*c]const win.Event) callconv(.c) void {
            const window: Window = .{ .raw = event.*.common.win };
            const context: *Context = @ptrCast(@alignCast(window.userdata()));
            const app = context.app;

            var curr: ?*WindowState = app.states.head;

            while (curr) |state| : (curr = state.next) {
                if (state.win.raw == window.raw) {
                    state.size = .{
                        .width = @floatFromInt(event.*.update.w),
                        .height = @floatFromInt(event.*.update.h),
                    };

                    render(app, state, true) catch |err| {
                        log.err("Window render err={}", .{err});
                    };
                    break;
                }
            }
        }
    }.callback);

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

    context.waker = try app.await(
        &context.display_c,
        struct {
            fn callback(completion: *Completion, loop: *Loop, res: anyerror!void) bool {
                res catch loop.stop();

                const ctx: *Context = @alignCast(@fieldParentPtr("display_c", completion));

                if (ctx.app.states.is_empty()) ctx.app.stop();

                win.pollEvents();

                var states = ctx.app.states;
                ctx.app.states = .empty;

                const chunks = ctx.app.chunks.allocator();

                while (states.pop()) |state| {
                    if (state.win.shouldClose()) {
                        state.deinit();

                        chunks.destroy(state);
                    } else {
                        render(ctx.app, state, false) catch |err| {
                            log.err("Window render err={}", .{err});
                        };

                        ctx.app.states.append(state);
                    }
                }

                return true;
            }
        }.callback,
    );

    const chunks = app.chunks.allocator();
    const window_state = try chunks.create(WindowState);

    try window_state.init(
        &app.renderer,
        .{
            .name = "Odyssey",
            .x = 0,
            .y = 0,
            .width = 800,
            .height = 600,
            .flags = win.WindowCenter | win.WindowFocus,
            .userdata = &context,
        },
        app.gpa,
        app.io,
    );

    errdefer window_state.deinit();

    app.states.append(window_state);

    const result = try macos.video.DisplayLink.createWithActiveCGDisplays();
    result.setOutputCallback(
        Waker,
        struct {
            fn callback(_: *macos.video.DisplayLink, ud: ?*Waker) void {
                if (ud) |waker| {
                    waker.wake() catch {};
                }
            }
        }.callback,
        &context.waker,
    ) catch |err| {
        log.warn("error configuring display link err={}", .{err});
        result.release();
        return;
    };

    try result.start();

    app.run(.until_done);
}

pub fn render(app: *App, state: *WindowState, sync: bool) !void {
    {
        const view = &state.view_state;
        try view.begin(.{
            .width = state.size.width,
            .height = state.size.height,
        });
        defer view.finish();

        try view.pushAttrs(&.{ .{ .width = .grow }, .{ .height = .grow } });
        defer view.popAttrs(&.{ .width, .height });

        try view.nextAttrs(&.{
            .{ .width = .{ .fixed = 100 } },
            .{ .color = .{ 1.0, 0.0, 0.0, 1.0 } },
        });
        _ = try view.block(.{});

        try view.nextAttrs(&.{
            .{ .color = .{ 0.0, 1.0, 0.0, 1.0 } },
            .{ .height_shrink = 0.0 },
            .{ .width_shrink = 0.0 },
        });
        _ = try view.block(.{});

        try view.nextAttrs(&.{
            .{ .width = .{ .fixed = 100 } },
            .{ .color = .{ 0.0, 0.0, 1.0, 1.0 } },
        });
        _ = try view.block(.{});
    }

    const frame = state.render_handle.nextFrame();
    errdefer state.render_handle.releaseFrame();

    try frame.uniform(.{
        .viewport_size = .{ state.size.width, state.size.height },
    });

    var box = state.view_state.root;
    while (box) |current| : (box = current.nextPreOrder()) {
        try frame.rect(.{
            .position = .{
                current.abs_position[0],
                current.abs_position[1],
                current.abs_position[0] + current.size[0],
                current.abs_position[1] + current.size[1],
            },
            .color_0 = current.color,
            .color_1 = current.color,
            .color_2 = current.color,
            .color_3 = current.color,
        });
    }

    renderer.render(&app.renderer, &state.render_handle, frame, sync);
}
