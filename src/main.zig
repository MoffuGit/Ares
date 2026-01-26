const std = @import("std");
const datastruct = @import("datastruct/mod.zig");
const yoga = @import("yoga");

const Box = @import("element/Box.zig");
const Element = @import("element/mod.zig").Element;
const Node = @import("element/Node.zig");
const Style = @import("element/mod.zig").Style;
const Buffer = @import("Buffer.zig");
const HitGrid = @import("HitGrid.zig");

const vaxis = @import("vaxis");
const Cell = vaxis.Cell;

const GPA = std.heap.GeneralPurposeAllocator(.{});

const App = @import("App.zig");
const events = @import("events/mod.zig");
const EventContext = events.EventContext;

const split = @import("split/mod.zig");
const SplitTree = split.Tree;

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

    const tree = try SplitTree.create(alloc);
    defer tree.destroy();

    try app.window.root.addChild(tree.element);

    app.run() catch |err| {
        log.err("App exit with an err: {}", .{err});
    };
}
