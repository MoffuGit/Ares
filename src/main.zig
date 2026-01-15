const std = @import("std");
const datastruct = @import("datastruct/mod.zig");

const vaxis = @import("vaxis");
const Cell = vaxis.Cell;

const App = @import("App.zig");
const Root = @import("window/Root.zig");

const log = std.log.scoped(.main);

const global = &@import("global.zig").state;

pub fn main() !void {
    try global.init();
    defer global.deinit();

    const root = try global.alloc.create(Root);
    defer global.alloc.destroy(root);

    try root.init();

    var app = try global.alloc.create(App);
    defer global.alloc.destroy(app);

    try app.init(global.alloc, root);
    defer app.deinit();

    app.run() catch |err| {
        log.err("App exit with an err: {}", .{err});
    };
}
