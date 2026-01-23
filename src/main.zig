const std = @import("std");
const datastruct = @import("datastruct/mod.zig");
const yoga = @import("yoga");

const Box = @import("element/Box.zig");
const Element = @import("element/mod.zig").Element;
const Style = @import("element/mod.zig").Style;

const vaxis = @import("vaxis");
const Cell = vaxis.Cell;

const GPA = std.heap.GeneralPurposeAllocator(.{});

const App = @import("App.zig");
const events = @import("events/mod.zig");
const EventContext = events.EventContext;

const log = std.log.scoped(.main);

pub fn keyPressFn(element: *Element, ctx: *EventContext, key: vaxis.Key) void {
    if (key.matches('c', .{ .ctrl = true })) {
        if (element.context) |app_ctx| {
            app_ctx.stopApp() catch {};
        }
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
        .root_opts = .{
            .keyPressFn = keyPressFn,
            .style = .{
                .flex_direction = .row,
                .width = .{ .percent = 100 },
                .height = .{ .percent = 100 },
            },
        },
    });
    defer app.destroy();

    const blue_box = try Box.create(alloc, .{
        .id = "blue-box",
        .style = .{
            .width = .{ .percent = 33.33 },
            .height = .{ .percent = 100 },
        },
        .background = .{ .rgb = .{ 0, 0, 255 } },
    });
    defer blue_box.destroy(alloc);

    const red_box = try Box.create(alloc, .{
        .id = "red-box",
        .style = .{
            .flex_grow = 1,
            .height = .{ .percent = 100 },
        },
        .background = .{ .rgb = .{ 255, 0, 0 } },
    });
    defer red_box.destroy(alloc);

    try app.window.root.addChild(&blue_box.element);
    try app.window.root.addChild(&red_box.element);

    app.run() catch |err| {
        log.err("App exit with an err: {}", .{err});
    };
}
