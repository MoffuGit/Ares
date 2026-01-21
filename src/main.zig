const std = @import("std");
const datastruct = @import("datastruct/mod.zig");

const Box = @import("element/Box.zig");

const vaxis = @import("vaxis");
const Cell = vaxis.Cell;

const GPA = std.heap.GeneralPurposeAllocator(.{});

const App = @import("App.zig");
const AppContext = @import("AppContext.zig");
const events = @import("events/mod.zig");
const EventContext = events.EventContext;

const log = std.log.scoped(.main);

pub fn keyPressFn(app_ctx: *AppContext, ctx: *EventContext, key: vaxis.Key) void {
    if (key.matches('c', .{ .ctrl = true })) {
        app_ctx.stopApp() catch {};
        ctx.stopPropagation();
    }
}

pub fn main() !void {
    var gpa: GPA = .{};
    defer if (gpa.deinit() == .leak) {
        std.log.info("We have leaks 🔥", .{});
    };

    const alloc = gpa.allocator();

    var app = try App.create(alloc, .{
        .keyPressFn = keyPressFn,
    });
    defer app.destroy();

    app.run() catch |err| {
        log.err("App exit with an err: {}", .{err});
    };
}
