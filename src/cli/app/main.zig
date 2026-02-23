const std = @import("std");
const tui = @import("tui");
const core = @import("core");

const global = @import("global.zig");
const Bridge = @import("bridge.zig");

const Element = tui.Element;
const App = tui.App;

const GPA = std.heap.GeneralPurposeAllocator(.{});

pub fn main() !void {
    var gpa: GPA = .{};
    defer if (gpa.deinit() == .leak) {
        std.log.info("We have leaks 🔥", .{});
    };

    const alloc = gpa.allocator();

    const app = try App.create(alloc, .{
        .on_wakeup = onWakeup,
    });
    defer app.destroy();

    const engine = try core.Engine.create(alloc, .{
        .callback = wakeLoop,
        .userdata = @ptrCast(app),
    });
    defer engine.destroy();

    var bridge = Bridge.init(alloc, engine, app);
    defer bridge.deinit();

    global.bridge = &bridge;
    global.engine = engine;

    try app.root().addEventListener(.key_press, Element, app.root(), keyPressFn);

    engine.dispatch(.{ .reload_settings = "settings" });

    app.run() catch |err| {
        std.log.err("App exit with an err: {}", .{err});
    };
}

fn wakeLoop(userdata: ?*anyopaque) void {
    const a: *App = @ptrCast(@alignCast(userdata orelse return));
    a.loop.wakeup.notify() catch {};
}

fn onWakeup(app: *App) void {
    _ = app;
    global.bridge.drainEngineEvents();
}

pub fn keyPressFn(_: *Element, data: Element.ElementEvent) void {
    const key = data.event.key_press;
    if (key.matches('c', .{ .ctrl = true })) {
        if (data.element.context) |ctx| {
            ctx.stop() catch {};
        }
        data.ctx.stopPropagation();
    }
}
