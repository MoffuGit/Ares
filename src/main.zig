const std = @import("std");
const datastruct = @import("datastruct/mod.zig");

const vaxis = @import("vaxis");
const Cell = vaxis.Cell;

const App = @import("App.zig");
const Root = @import("window/Root.zig");
const Box = @import("window/Box.zig");

const log = std.log.scoped(.main);

const global = &@import("global.zig").state;

pub fn main() !void {
    try global.init();
    defer global.deinit();

    const root = try Root.create(global.alloc);
    defer root.element.destroy();

    const box = try Box.create(global.alloc, .{
        .height = 20,
        .width = 20,
    });
    defer box.element.destroy();

    try root.element.addChild(&box.element);

    var app = try App.create(global.alloc, .{
        .root = &root.element,
    });
    defer app.destroy();

    app.run() catch |err| {
        log.err("App exit with an err: {}", .{err});
    };
}
